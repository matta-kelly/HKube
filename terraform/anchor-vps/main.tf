# ==============================================================================
# Anchor VPS - Main Configuration
# ==============================================================================
# Creates a small VPS on Hetzner Cloud to run Headscale + HAProxy
# This is the networking foundation for the hybrid cluster
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
# SSH Key
# ------------------------------------------------------------------------------
resource "hcloud_ssh_key" "default" {
  name       = "${var.name}-key"
  public_key = var.ssh_public_key
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
}
# ------------------------------------------------------------------------------
# Server
# ------------------------------------------------------------------------------
resource "hcloud_server" "anchor" {
  name        = var.name
  image       = var.image
  server_type = var.server_type
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.default.id]
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