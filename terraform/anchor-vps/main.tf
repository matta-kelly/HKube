# ==============================================================================
# Anchor VPS - Main Configuration
# ==============================================================================
# Creates the anchor VPS in Oregon (Hetzner hil datacenter).
# Runs: Headscale, Caddy, Forgejo, HAProxy.
#
# Usage:
#   export HCLOUD_TOKEN="your-token"
#   export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
#   terraform init
#   terraform apply
#
# ==============================================================================
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}
# ------------------------------------------------------------------------------
# Provider
# ------------------------------------------------------------------------------
provider "hcloud" {
  token = var.hcloud_token
}
# ------------------------------------------------------------------------------
# SSH Key (use existing from Hetzner account)
# ------------------------------------------------------------------------------
data "hcloud_ssh_key" "default" {
  fingerprint = var.ssh_key_fingerprint
}
# ------------------------------------------------------------------------------
# Firewall
# ------------------------------------------------------------------------------
resource "hcloud_firewall" "anchor" {
  name = "${var.name}-firewall"
  # SSH
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  # Headscale HTTPS
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  # Headscale HTTP (for ACME)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  # DERP/STUN (for NAT traversal)
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "3478"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Forgejo Git SSH
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "2222"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}
# ------------------------------------------------------------------------------
# Server
# ------------------------------------------------------------------------------
resource "hcloud_server" "anchor" {
  name        = var.name
  image       = var.image
  server_type = var.server_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.anchor.id]
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  labels = {
    purpose = "anchor"
    managed = "terraform"
  }
}
