#!/bin/bash
set -e

# Get Terraform outputs
HEADSCALE_IP=$(cd terraform/headscale-vps && terraform output -raw ipv4_address 2>/dev/null || echo "")

# Source .env for non-Terraform vars
source .env

# Generate inventory
cat > ansible/inventory.yml << EOF
all:
  vars:
    admin_user: "${HEADSCALE_USER:-mkultra}"
    ssh_public_key_file: "${SSH_PUBLIC_KEY_FILE:-~/.ssh/id_ed25519_hetzner.pub}"
    github_user: "${GITHUB_USER}"
    github_token: "${GITHUB_TOKEN}"
    github_repo: "${GITHUB_REPO:-h-kube}"
    github_branch: "${GITHUB_BRANCH:-main}"
    k3s_version: "v1.31.3+k3s1"
    cilium_version: "1.16.4"
    sops_version: "3.9.0"

  children:
    headscale:
      hosts:
        headscale-vps:
          ansible_host: ${HEADSCALE_IP}
          ansible_user: root
          ansible_ssh_private_key_file: ${SSH_PUBLIC_KEY_FILE%.pub}
          headscale_version: "0.23.0"
          headscale_domain: "${HEADSCALE_DOMAIN}"
          headscale_base_domain: "${HEADSCALE_BASE_DOMAIN}"
          firewall_allow_ports:
            - { port: "80", proto: "tcp" }
            - { port: "443", proto: "tcp" }
            - { port: "3478", proto: "udp" }

    k3s_cluster:
      hosts:
        home-server:
          ansible_host: ${SERVER_IP}
          ansible_user: ${SERVER_USER:-mkultra}
          ansible_ssh_private_key_file: ${SSH_PUBLIC_KEY_FILE%.pub}
          server_ip: ${SERVER_IP}
          firewall_allow_ports:
            - { port: "6443", proto: "tcp" }
            - { port: "80", proto: "tcp" }
            - { port: "443", proto: "tcp" }
EOF

echo "Generated ansible/inventory.yml"