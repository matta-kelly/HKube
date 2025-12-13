# ==============================================================================
# H-Kube Makefile
# ==============================================================================

.PHONY: help setup headscale headscale-destroy headscale-init headscale-configure headscale-ssh bootstrap ansible-ping encrypt decrypt

help:
	@echo "H-Kube Commands:"
	@echo ""
	@echo "  Setup:"
	@echo "    make setup              - Initial setup (creates .env, .vault_password)"
	@echo ""
	@echo "  Headscale VPS:"
	@echo "    make headscale          - Create Headscale VPS (Terraform)"
	@echo "    make headscale-destroy  - Destroy Headscale VPS"
	@echo "    make headscale-init     - First-time VPS config (as root)"
	@echo "    make headscale-configure - Re-run VPS config (as admin user)"
	@echo "    make headscale-ssh      - SSH into Headscale VPS"
	@echo ""
	@echo "  Home Server:"
	@echo "    make bootstrap          - Full k3s + Cilium + Flux setup"
	@echo "    make ansible-ping       - Test Ansible connectivity"
	@echo ""
	@echo "  Secrets:"
	@echo "    make encrypt FILE=...   - Encrypt with SOPS"
	@echo "    make decrypt FILE=...   - Decrypt with SOPS"

# ------------------------------------------------------------------------------
# Initial Setup
# ------------------------------------------------------------------------------

setup:
	@echo "Setting up h-kube..."
	@test -f .env || cp .env.example .env
	@./scripts/ensure-vault.sh
	@mkdir -p ansible/group_vars/all
	@bash -c 'source .env 2>/dev/null && \
		if [ -n "$$HCLOUD_TOKEN" ] && command -v hcloud &>/dev/null; then \
			hcloud context list | grep -q h-kube || echo "$$HCLOUD_TOKEN" | hcloud context create h-kube; \
		fi'
	@echo ""
	@echo "Done. Edit .env with your values, then run: make headscale"

# ------------------------------------------------------------------------------
# Headscale VPS - Terraform
# ------------------------------------------------------------------------------

headscale:
	@test -f .env || (echo "Error: .env not found. Run: make setup" && exit 1)
	@bash -c 'source .env && test -n "$$HCLOUD_TOKEN" || (echo "HCLOUD_TOKEN not set" && exit 1)'
	@bash -c 'source .env && test -n "$$SSH_PUBLIC_KEY_FILE" || (echo "SSH_PUBLIC_KEY_FILE not set" && exit 1)'
	@echo "Creating Headscale VPS..."
	@bash -c 'source .env && \
		export TF_VAR_hcloud_token="$$HCLOUD_TOKEN" && \
		export TF_VAR_ssh_public_key="$$(cat $$SSH_PUBLIC_KEY_FILE)" && \
		cd terraform/headscale-vps && \
		terraform init && \
		terraform apply'
	@./scripts/generate-inventory.sh
	@echo ""
	@echo "=========================================="
	@echo "Inventory generated. Run: make headscale-init"
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
	@./scripts/ensure-vault.sh
	@test -f ansible/inventory.yml || (echo "Run 'make headscale' first" && exit 1)
	@echo "Initializing Headscale VPS (first run, as root)..."
	@cd ansible && ansible-playbook headscale.yaml
	@echo ""
	@echo "=========================================="
	@echo "Done! Root login now disabled."
	@echo "Run: make headscale-ssh"
	@echo "=========================================="

headscale-configure:
	@./scripts/ensure-vault.sh
	@test -f ansible/inventory.yml || (echo "Run 'make headscale' first" && exit 1)
	@echo "Configuring Headscale VPS..."
	@bash -c 'source .env && \
		cd ansible && \
		ansible-playbook headscale.yaml -e "ansible_user=$${HEADSCALE_USER:-mkultra}"'


headscale-ssh:
	@bash -c 'source .env && \
		HEADSCALE_IP=$$(cd terraform/headscale-vps && terraform output -raw ipv4_address) && \
		ssh -i $${SSH_PUBLIC_KEY_FILE%.pub} $${HEADSCALE_USER:-mkultra}@$$HEADSCALE_IP'

# ------------------------------------------------------------------------------
# Home Server - Ansible
# ------------------------------------------------------------------------------

bootstrap:
	@./scripts/ensure-vault.sh
	@test -f ansible/inventory.yml || (echo "Run 'make headscale' first" && exit 1)
	@echo "Bootstrapping k3s cluster..."
	@cd ansible && ansible-playbook site.yaml

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