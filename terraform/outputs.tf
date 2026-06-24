output "public_ip" {
  description = "Public IP of the k3s node"
  value       = aws_instance.k3s.public_ip
}

output "fetch_kubeconfig" {
  description = "Command to copy the cluster kubeconfig to your machine"
  value       = "scp ubuntu@${aws_instance.k3s.public_ip}:/home/ubuntu/kubeconfig.yaml ./kubeconfig && export KUBECONFIG=$PWD/kubeconfig"
}

output "app_url" {
  description = "URL where the ingress will serve the app once deployed"
  value       = "http://${aws_instance.k3s.public_ip}"
}
