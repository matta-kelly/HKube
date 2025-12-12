# ==============================================================================
# Headscale VPS - Outputs
# ==============================================================================
# These values are used by Ansible to configure the server
# ==============================================================================

output "ipv4_address" {
  description = "Public IPv4 address of the Headscale server"
  value       = hcloud_server.headscale.ipv4_address
}

output "ipv6_address" {
  description = "Public IPv6 address of the Headscale server"
  value       = hcloud_server.headscale.ipv6_address
}

output "server_id" {
  description = "Hetzner server ID"
  value       = hcloud_server.headscale.id
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh root@${hcloud_server.headscale.ipv4_address}"
}

output "ansible_host_entry" {
  description = "Entry for Ansible inventory"
  value       = <<-EOT
    headscale:
      ansible_host: ${hcloud_server.headscale.ipv4_address}
      ansible_user: root
  EOT
}