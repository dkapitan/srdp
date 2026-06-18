# Self-hosted CI runner inside the spoke Private Network.
#
# Azure used an Azure DevOps VMSS agent pool; SRDP lives on GitHub, so this is a
# GitHub Actions self-hosted runner instead. Same purpose: a CI worker that lives
# INSIDE the VPC so Terraform/kubectl can reach the private estate — the
# Kapsule API (locked by ACL to the PN), RDB, and the internal Traefik LB —
# which a hosted runner on the public internet cannot.
#
# No public IP: outbound only, via the spoke Public Gateway (NAT). Provide a
# runner registration token via Secret Manager / a CI secret.

variable "name" {
  type    = string
  default = "ci-runner"
}
variable "private_network_id" { type = string }
variable "ssh_public_key" { type = string }
variable "instance_type" {
  type    = string
  default = "PLAY2-MICRO"
}
variable "github_repo_url" {
  type        = string
  description = "https://github.com/<org>/<repo> the runner registers against."
}
variable "github_runner_token" {
  type        = string
  sensitive   = true
  description = "Short-lived runner registration token (from repo Settings > Actions > Runners)."
}
variable "runner_labels" {
  type    = string
  default = "self-hosted,scaleway"
}
variable "tags" {
  type    = list(string)
  default = []
}

resource "scaleway_instance_security_group" "this" {
  name                    = "sg-${var.name}"
  inbound_default_policy  = "drop" # outbound-only worker
  outbound_default_policy = "accept"
  tags                    = var.tags
}

resource "scaleway_instance_server" "this" {
  name              = "vm-${var.name}"
  type              = var.instance_type
  image             = "ubuntu_jammy"
  security_group_id = scaleway_instance_security_group.this.id
  tags              = var.tags

  # No ip_id => no public IP; egress goes through the Public Gateway on the PN.
  private_network {
    pn_id = var.private_network_id
  }

  user_data = {
    cloud-init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      ssh_public_key      = var.ssh_public_key
      github_repo_url     = var.github_repo_url
      github_runner_token = var.github_runner_token
      runner_labels       = var.runner_labels
    })
  }
}

output "server_id" { value = scaleway_instance_server.this.id }
