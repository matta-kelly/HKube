# ==============================================================================
# Anchor Oregon VPS - Variables
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

variable "ssh_key_fingerprint" {
  description = "SSH key fingerprint (MD5) to look up existing key in Hetzner"
  type        = string
  default     = "33:0f:a1:17:ea:59:25:24:20:9c:a4:87:9e:93:78:4b"
}

# ------------------------------------------------------------------------------
# Optional - defaults work for most cases
# ------------------------------------------------------------------------------

variable "name" {
  description = "Server name"
  type        = string
  default     = "Anchor-Oregon"    # Different from existing "Anchor" to avoid collision
}

variable "server_type" {
  description = "Hetzner server type (~$10/mo for Oregon)"
  type        = string
  default     = "cpx21"  # Oregon uses CPX types, not CX
}

variable "location" {
  description = "Hetzner datacenter (hil=Oregon, nbg1=Germany, fsn1=Germany, ash=Virginia)"
  type        = string
  default     = "hil"  # Oregon - closer to US West Coast
}

variable "image" {
  description = "OS image"
  type        = string
  default     = "ubuntu-24.04"
}
