# ==============================================================================
# Control Plane VPS - Main Configuration
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
data "hcloud_ssh_key" "default" {
  name = "Anchor-key"
}

# ------------------------------------------------------------------------------
# Firewall
# ------------------------------------------------------------------------------
resource "hcloud_firewall" "control_plane" {
  name = "${var.name}-firewall"

  # SSH
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# ------------------------------------------------------------------------------
# Server
# ------------------------------------------------------------------------------
resource "hcloud_server" "control_plane" {
  name         = var.name
  image        = var.image
  server_type  = var.server_type
  location     = var.location
  ssh_keys = [data.hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.control_plane.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  labels = {
    purpose = "control-plane"
    managed = "terraform"
  }
}