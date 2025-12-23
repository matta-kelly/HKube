# ==============================================================================
# Anchor VPS - Variables
# ==============================================================================
# All values come from environment via TF_VAR_ prefix
# Source .env before running: source ../../.env
# ==============================================================================

# ------------------------------------------------------------------------------
# Required - set in .env
# ------------------------------------------------------------------------------

variable "hcloud_token" {
  description = "Hetzner Cloud API token (from TF_VAR_hcloud_token)"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key (from TF_VAR_ssh_public_key)"
  type        = string
}

# ------------------------------------------------------------------------------
# Optional - defaults work for most cases
# ------------------------------------------------------------------------------

variable "name" {
  description = "Server name"
  type        = string
  default     = "Anchor"
}

variable "server_type" {
  description = "Hetzner server type (~$5/mo)"
  type        = string
  default     = "cx22"
}

variable "location" {
  description = "Hetzner datacenter"
  type        = string
  default     = "hil"
}

variable "image" {
  description = "OS image"
  type        = string
  default     = "ubuntu-24.04"
}