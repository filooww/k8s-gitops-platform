variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "EC2 instance type for the k3s node"
  type        = string
  default     = "t3.small"
}

variable "use_spot" {
  description = "Provision the node as a Spot instance (cheaper, can be reclaimed)"
  type        = bool
  default     = true
}

variable "ssh_public_key" {
  description = "Public SSH key contents used to access the node"
  type        = string
}

variable "allowed_cidr" {
  description = "CIDR allowed to reach SSH (22) and the k3s API (6443). Lock this to your IP."
  type        = string
  default     = "0.0.0.0/0"
}

variable "name" {
  description = "Name prefix for created resources"
  type        = string
  default     = "k8s-gitops"
}
