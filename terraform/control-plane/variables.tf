# ==============================================================================
# Control Plane VPS - Variables
# ==============================================================================

variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
}

variable "name" {
  description = "Server name"
  type        = string
  default     = "cloud-cp-1"
}

variable "server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cpx21"
}

variable "location" {
  description = "Hetzner datacenter"
  type        = string
  default     = "ash"
}

variable "image" {
  description = "OS image"
  type        = string
  default     = "ubuntu-24.04"
}