# ==============================================================================
# Control Plane VPS - Outputs
# ==============================================================================

output "ipv4_address" {
  description = "Public IPv4 address"
  value       = hcloud_server.control_plane.ipv4_address
}

output "ipv6_address" {
  description = "Public IPv6 address"
  value       = hcloud_server.control_plane.ipv6_address
}

output "server_id" {
  description = "Hetzner server ID"
  value       = hcloud_server.control_plane.id
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh root@${hcloud_server.control_plane.ipv4_address}"
}