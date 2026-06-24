# Copy to terraform.tfvars and fill in. terraform.tfvars is gitignored.
region         = "eu-central-1"
instance_type  = "t3.small"
use_spot       = true
ssh_public_key = "ssh-ed25519 AAAA... your-key"
# Lock this down to your own IP for SSH/API access:
allowed_cidr = "0.0.0.0/0"
