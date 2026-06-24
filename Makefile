CLUSTER ?= gitops
IMAGE   ?= k8s-gitops-demo:dev

.PHONY: help cluster-up image deploy-local argocd monitoring bootstrap \
        urls grafana-pw load k6 clean

BASE_URL ?= http://myapp.localhost:8080

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

cluster-up: ## Create the local k3d cluster (ingress on :8080)
	k3d cluster create $(CLUSTER) --servers 1 --agents 1 -p "8080:80@loadbalancer" --wait
	$(MAKE) image

image: ## Build the app image and import it into the cluster
	docker build -t $(IMAGE) ./app
	k3d image import $(IMAGE) -c $(CLUSTER)

monitoring: ## Install kube-prometheus-stack via Helm
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
	  --version 87.2.0 -n monitoring --create-namespace \
	  -f monitoring/values.yaml --wait

monitoring-telegram: ## Install/upgrade monitoring with the Telegram alert overlay
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
	  --version 87.2.0 -n monitoring --create-namespace \
	  -f monitoring/values.yaml -f monitoring/alertmanager-telegram.yaml --wait

deploy-local: ## Deploy the app chart with the locally-built image
	helm upgrade --install myapp charts/myapp -n myapp --create-namespace \
	  --set image.repository=k8s-gitops-demo --set image.tag=dev \
	  --set image.pullPolicy=Never --wait

argocd: ## Install ArgoCD and apply the app-of-apps root (real GitOps loop)
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl -n argocd rollout status deploy/argocd-server --timeout=180s
	kubectl apply -f argocd/project.yaml
	kubectl apply -f argocd/root-app.yaml

bootstrap: cluster-up monitoring deploy-local ## One-shot local stack (Helm-driven)
	@echo "Stack up. Run 'make urls' for endpoints."

urls: ## Print useful endpoints
	@echo "App     : http://myapp.localhost:8080  (add '127.0.0.1 myapp.localhost' to /etc/hosts)"
	@echo "Grafana : kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80  -> http://localhost:3000 (admin / make grafana-pw)"
	@echo "Prom    : kubectl -n monitoring port-forward svc/monitoring-prometheus 9090:9090"
	@echo "ArgoCD  : kubectl -n argocd port-forward svc/argocd-server 8081:443 -> https://localhost:8081"

grafana-pw: ## Print the Grafana admin password
	@kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo

load: ## Generate load with a simple curl loop (Ctrl-C to stop)
	@echo "Hammering /work ... watch 'kubectl -n myapp get hpa,pods'"
	@while true; do curl -s "$(BASE_URL)/work?iterations=400000" >/dev/null; done

k6: ## Run the k6 ramping load test (drives the HPA 2 -> 6)
	BASE_URL=$(BASE_URL) k6 run loadtest/script.js

clean: ## Delete the k3d cluster
	k3d cluster delete $(CLUSTER)
