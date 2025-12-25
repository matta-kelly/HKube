#!/bin/bash
set -e

# Source .env first
source .env

# Get IPs from terraform (empty string if not exists)
ANCHOR_IP=$(cd terraform/anchor-vps && terraform output -raw ipv4_address 2>/dev/null || echo "")
CP_IP=$(cd terraform/control-plane && terraform output -raw ipv4_address 2>/dev/null || echo "")

# Start inventory
cat > ansible/inventory.yml << EOF
all:
  vars:
    admin_user: "${ANCHOR_USER:-mkultra}"
    ssh_public_key_file: "${SSH_PUBLIC_KEY_FILE}"
    headscale_domain: "${HEADSCALE_DOMAIN}"
    headscale_base_domain: "${HEADSCALE_BASE_DOMAIN}"
    headscale_authkey: "${HEADSCALE_AUTHKEY}"
    github_user: "${GITHUB_USER}"
    github_repo: "${GITHUB_REPO:-h-kube}"
    github_branch: "${GITHUB_BRANCH:-main}"
    k3s_version: "v1.31.3+k3s1"
    cilium_version: "1.16.4"
    sops_version: "3.9.0"

  children:
EOF

# Anchor section (if exists)
if [ -n "$ANCHOR_IP" ]; then
cat >> ansible/inventory.yml << EOF
    anchor:
      hosts:
        anchor:
          ansible_host: ${ANCHOR_IP}
          ansible_user: ${ANCHOR_USER:-mkultra}
          ansible_ssh_private_key_file: ${SSH_PUBLIC_KEY_FILE%.pub}
          tailscale_hostname: "anchor"
          headscale_version: "0.23.0"
          headscale_domain: "${HEADSCALE_DOMAIN}"
          headscale_base_domain: "${HEADSCALE_BASE_DOMAIN}"
          firewall_allow_ports:
            - { port: "80", proto: "tcp" }
            - { port: "443", proto: "tcp" }
            - { port: "3478", proto: "udp" }
EOF
fi

# Control plane section (if exists)
if [ -n "$CP_IP" ]; then
cat >> ansible/inventory.yml << EOF
    control_planes:
      hosts:
        cloud-cp-1:
          ansible_host: ${CP_IP}
          ansible_user: ${ANCHOR_USER:-mkultra}
          ansible_ssh_private_key_file: ${SSH_PUBLIC_KEY_FILE%.pub}
          tailscale_hostname: "cloud-cp-1"
          firewall_allow_ports:
            - { port: "6443", proto: "tcp" }
EOF
fi

echo "Generated ansible/inventory.yml"