# ==============================================================================
# H-Kube Makefile
# ==============================================================================

.PHONY: help headscale headscale-destroy headscale-init headscale-configure headscale-ssh bootstrap ansible-ping encrypt decrypt

help:
	@echo "H-Kube Commands:"
	@echo ""
	@echo "  Headscale VPS:"
	@echo "    make headscale            - Create VPS (Terraform)"
	@echo "    make headscale-init       - First-time setup (as root)"
	@echo "    make headscale-configure  - Re-configure (as HEADSCALE_USER)"
	@echo "    make headscale-ssh        - SSH into VPS"
	@echo "    make headscale-destroy    - Destroy VPS"
	@echo ""
	@echo "  Home Server:"
	@echo "    make bootstrap            - Bootstrap k3s cluster"
	@echo "    make ansible-ping         - Test connectivity"
	@echo ""
	@echo "  Secrets:"
	@echo "    make encrypt FILE=...     - Encrypt with SOPS"
	@echo "    make decrypt FILE=...     - Decrypt with SOPS"
	@echo ""

# ------------------------------------------------------------------------------
# Headscale VPS - Terraform
# ------------------------------------------------------------------------------

headscale:
	@test -f .env || (echo "Error: .env not found" && exit 1)
	@bash -c 'source .env && test -n "$$HCLOUD_TOKEN" || (echo "HCLOUD_TOKEN not set" && exit 1)'
	@bash -c 'source .env && test -n "$$SSH_PUBLIC_KEY_FILE" || (echo "SSH_PUBLIC_KEY_FILE not set" && exit 1)'
	@echo "Creating Headscale VPS..."
	@bash -c 'source .env && \
		export TF_VAR_hcloud_token="$$HCLOUD_TOKEN" && \
		export TF_VAR_ssh_public_key="$$(cat $$SSH_PUBLIC_KEY_FILE)" && \
		cd terraform/headscale-vps && \
		terraform init && \
		terraform apply'
	@echo ""
	@echo "=========================================="
	@echo "Next steps:"
	@echo "  1. Add to .env: HEADSCALE_IP=<ip from above>"
	@echo "  2. Run: make headscale-init"
	@echo "=========================================="

headscale-destroy:
	@test -f .env || (echo "Error: .env not found" && exit 1)
	@bash -c 'source .env && \
		export TF_VAR_hcloud_token="$$HCLOUD_TOKEN" && \
		export TF_VAR_ssh_public_key="$$(cat $$SSH_PUBLIC_KEY_FILE)" && \
		cd terraform/headscale-vps && \
		terraform destroy'

# ------------------------------------------------------------------------------
# Headscale VPS - Ansible
# ------------------------------------------------------------------------------

headscale-init:
	@test -f .env || (echo "Error: .env not found" && exit 1)
	@bash -c 'source .env && test -n "$$HEADSCALE_IP" || (echo "HEADSCALE_IP not set" && exit 1)'
	@echo "Initializing Headscale VPS (first run, as root)..."
	@bash -c 'source .env && \
		cd ansible && \
		ansible-playbook headscale.yaml'
	@echo ""
	@echo "=========================================="
	@echo "Done! Root login now disabled."
	@echo ""
	@echo "Add to ~/.ssh/config:"
	@echo ""
	@bash -c 'source .env && echo "Host headscale"'
	@bash -c 'source .env && echo "  HostName $$HEADSCALE_IP"'
	@bash -c 'source .env && echo "  User $$HEADSCALE_USER"'
	@bash -c 'source .env && echo "  IdentityFile $$SSH_PUBLIC_KEY_FILE" | sed "s/.pub//"'
	@echo "  IdentitiesOnly yes"
	@echo ""
	@echo "Then: ssh headscale"
	@echo "=========================================="

headscale-configure:
	@test -f .env || (echo "Error: .env not found" && exit 1)
	@bash -c 'source .env && test -n "$$HEADSCALE_IP" || (echo "HEADSCALE_IP not set" && exit 1)'
	@echo "Configuring Headscale VPS (as $$HEADSCALE_USER)..."
	@bash -c 'source .env && \
		cd ansible && \
		ansible-playbook headscale.yaml -e "ansible_user=$$HEADSCALE_USER"'

headscale-ssh:
	@bash -c 'source .env && ssh -i $${SSH_PUBLIC_KEY_FILE%.pub} $$HEADSCALE_USER@$$HEADSCALE_IP'

# ------------------------------------------------------------------------------
# Home Server
# ------------------------------------------------------------------------------

bootstrap:
	@test -f .env || (echo "Error: .env not found" && exit 1)
	@bash -c 'source .env && test -n "$$SERVER_IP" || (echo "SERVER_IP not set" && exit 1)'
	@bash -c 'source .env && test -n "$$GITHUB_USER" || (echo "GITHUB_USER not set" && exit 1)'
	@bash -c 'source .env && test -n "$$GITHUB_TOKEN" || (echo "GITHUB_TOKEN not set" && exit 1)'
	@echo "Bootstrapping k3s cluster..."
	@bash -c 'source .env && \
		cd ansible && \
		ansible-playbook site.yaml'

ansible-ping:
	@bash -c 'source .env && \
		cd ansible && \
		ansible all -m ping'

# ------------------------------------------------------------------------------
# SOPS
# ------------------------------------------------------------------------------

encrypt:
	@test -n "$(FILE)" || (echo "Usage: make encrypt FILE=path/to/secret.yaml" && exit 1)
	@sops --encrypt --in-place $(FILE)
	@echo "Encrypted: $(FILE)"

decrypt:
	@test -n "$(FILE)" || (echo "Usage: make decrypt FILE=path/to/secret.yaml" && exit 1)
	@sops --decrypt --in-place $(FILE)
	@echo "Decrypted: $(FILE)"