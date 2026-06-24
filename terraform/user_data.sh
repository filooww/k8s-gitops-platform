#!/bin/bash
set -euxo pipefail

# Install k3s. Public IP is added as a TLS SAN so the fetched kubeconfig works
# from your laptop. kubeconfig is world-readable for easy copy (demo only).
PUBLIC_IP="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"

curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --tls-san "${PUBLIC_IP}"

# Rewrite the kubeconfig server address from 127.0.0.1 to the public IP.
until [ -f /etc/rancher/k3s/k3s.yaml ]; do sleep 2; done
sed "s/127.0.0.1/${PUBLIC_IP}/" /etc/rancher/k3s/k3s.yaml > /home/ubuntu/kubeconfig.yaml
chown ubuntu:ubuntu /home/ubuntu/kubeconfig.yaml
