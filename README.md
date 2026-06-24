# k8s-gitops-platform

[![CI](https://github.com/filooww/k8s-gitops-platform/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/filooww/k8s-gitops-platform/actions/workflows/ci.yaml)
[![IaC scan](https://github.com/filooww/k8s-gitops-platform/actions/workflows/iac-scan.yaml/badge.svg?branch=main)](https://github.com/filooww/k8s-gitops-platform/actions/workflows/iac-scan.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)
![Argo CD](https://img.shields.io/badge/Argo%20CD-EF7B4D?logo=argo&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?logo=grafana&logoColor=white)

Deploys a FastAPI service to Kubernetes using GitOps, with Prometheus/Grafana
monitoring and a CI pipeline that scans images before they ship.

When you push to `main`, CI builds the image, scans it, pushes it to GHCR, and
writes the new tag into the Helm values. ArgoCD notices the commit and syncs the
cluster. The pipeline itself never touches the cluster with `kubectl`; everything
goes through git.

![architecture](docs/architecture.svg)

## What it demonstrates

| Area              | Tech                                                                 |
| ----------------- | ------------------------------------------------------------------- |
| Containerization  | Multi-stage **Dockerfile**, non-root, read-only rootfs, healthcheck |
| Packaging         | **Helm** chart (Deployment, Service, Ingress, HPA, ConfigMap, Secret, ServiceMonitor, PrometheusRule) |
| GitOps            | **ArgoCD** app-of-apps, automated sync + self-heal, Helm multi-source |
| Observability     | **Prometheus** scrape via ServiceMonitor, **Grafana** dashboard, **Alertmanager → Telegram** |
| Autoscaling       | **HPA** v2 on CPU, driven by metrics-server; **k6** ramping load test |
| CI/CD             | **GitHub Actions**: tests, helm lint, build, **Trivy** CVE scan, GHCR push, GitOps tag bump |
| DevSecOps         | Trivy image scan (fail on CRITICAL/HIGH) + Trivy IaC misconfig scan → SARIF in Security tab |
| IaC (cloud)       | **Terraform** module: k3s on EC2 (Spot) for the cloud version       |

## Repository layout

```
app/                 FastAPI service exposing /metrics, /health, /work  + Dockerfile + tests
charts/myapp/        Helm chart for the app (+ bundled Grafana dashboard + PrometheusRule)
monitoring/          kube-prometheus-stack values + Alertmanager→Telegram overlay
loadtest/            k6 ramping load test that drives the HPA
argocd/              AppProject + app-of-apps root + Applications (myapp, monitoring)
terraform/           k3s-on-EC2 module (Spot) for a cloud deployment
.github/workflows/   ci.yaml (build/scan/push/bump) + iac-scan.yaml (Trivy config)
Makefile             one-command local stack
```

## Local quickstart (k3d)

Requires Docker, `kubectl`, `helm`, `k3d`.

```bash
make bootstrap        # create k3d cluster + install monitoring + deploy the app via Helm
make urls             # print Grafana / Prometheus / app endpoints
echo "127.0.0.1 myapp.localhost" | sudo tee -a /etc/hosts
curl http://myapp.localhost:8080/         # hit the app through the Traefik ingress
```

Show the autoscaler reacting to load:

```bash
make k6               # ramping k6 load test against /work
watch kubectl -n myapp get hpa,pods   # replicas climb 2 → 6
```

`make load` is a simpler curl-loop alternative. Under the k6 ramp the HPA was
observed at `cpu: 170%/60%` holding **6/6** replicas, then scaling back down on
cool-down.

### Verified working

I ran all of this on a local k3d cluster:

- both app pods scraped by Prometheus (`http://…:8000/metrics`, target `health=up`)
- `http_requests_total` and the latency histograms are queryable in Prometheus
- Grafana auto-loads the "myapp / FastAPI service" dashboard via the sidecar
- HPA reads CPU from metrics-server and scales 2 → 6 → 2 around the k6 load (below)

The bundled Grafana dashboard during a `make k6` run. It shows request rate,
p95/p50 latency, a 0% error rate, in-flight requests, and the HPA scaling 2 → 6 → 2:

![grafana dashboard](docs/grafana-dashboard.png)

## Alerting (Telegram)

`charts/myapp` ships a `PrometheusRule` with three alerts (`MyappTargetDown`,
`MyappHighErrorRate`, `MyappHighLatencyP95`); they load into Prometheus and
evaluate. To route firing alerts to Telegram, install the monitoring stack with
the overlay:

```bash
# put your @BotFather token + chat id in monitoring/alertmanager-telegram.yaml
make monitoring-telegram
```

The overlay adds a Telegram receiver to Alertmanager and routes everything from
the `myapp` namespace plus any `severity: critical` alert to your chat.

## The GitOps loop (real cluster)

The Helm quickstart above is the fast path. To run the full GitOps flow:

```bash
make argocd           # install ArgoCD + apply the app-of-apps root
```

ArgoCD then reconciles everything under `argocd/apps/` from this git repo:
`myapp` (the Helm chart) and `monitoring` (kube-prometheus-stack pulled from the
upstream Helm repo, with values sourced from this repo via a `$values` reference).

> Point `repoURL` in `argocd/` and the image `repository` in `charts/myapp/values.yaml`
> at your own GitHub/GHCR before syncing.

## CI/CD

`.github/workflows/ci.yaml` on push to `main`:

1. `test` runs pytest against the app.
2. `helm-lint` runs `helm lint` plus a render check.
3. `build-scan-push` builds the image, scans it with Trivy, and pushes to GHCR. All CRITICAL/HIGH findings go to the Security tab as SARIF, but only a CRITICAL in our own dependencies fails the build, so a transient base-image CVE won't flip the badge red.
4. `bump-manifest` writes the new image tag into `charts/myapp/values.yaml` and commits it with `[skip ci]`, which ArgoCD then deploys.

`.github/workflows/iac-scan.yaml` runs `trivy config` over Helm/manifests/Terraform.

## Cloud deployment (Terraform)

```bash
cd terraform
cp example.tfvars terraform.tfvars   # set ssh_public_key, lock allowed_cidr to your IP
terraform init && terraform apply
terraform output fetch_kubeconfig    # copies the kubeconfig to your machine
```

Provisions a Spot EC2 node, installs k3s via cloud-init, and exposes the API +
Traefik ingress. From there the GitOps loop is identical to local.

## Cleanup

```bash
make clean            # delete the k3d cluster
cd terraform && terraform destroy
```
