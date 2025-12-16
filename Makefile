# ==============================================================================
# H-Kube Makefile
# ==============================================================================

.PHONY: help setup headscale headscale-destroy headscale-init headscale-configure headscale-ssh

help:
	@echo "H-Kube Commands:"
	@echo ""
	@echo "  Setup:"
	@echo "    make setup              - Initial setup (creates .env)"
	@echo ""
	@echo "  Headscale VPS:"
	@echo "    make headscale          - Create Headscale VPS (Terraform)"
	@echo "    make headscale-destroy  - Destroy Headscale VPS"
	@echo "    make headscale-init     - First-time VPS config (as root)"
	@echo "    make headscale-configure - Re-run VPS config (as admin user)"
	@echo "    make headscale-ssh      - SSH into Headscale VPS"

# ------------------------------------------------------------------------------
# Initial Setup
# ------------------------------------------------------------------------------

setup:
	@echo "Setting up h-kube..."
	@test -f .env || cp .env.example .env
	@bash -c 'source .env 2>/dev/null && \
		if [ -n "$$HCLOUD_TOKEN" ] && command -v hcloud &>/dev/null; then \
			hcloud context list | grep -q h-kube || echo "$$HCLOUD_TOKEN" | hcloud context create h-kube; \
		fi'
	@echo ""
	@echo "Done. Edit .env with your values, then run: make headscale"


# ------------------------------------------------------------------------------
# Python Virtual Environment
# ------------------------------------------------------------------------------

venv:
	@if [ ! -d ".venv" ]; then \
		echo "Creating Python virtual environment..."; \
		python3 -m venv .venv; \
		. .venv/bin/activate && pip install --upgrade pip && pip install ansible; \
		echo "Virtual environment created."; \
	fi


# ------------------------------------------------------------------------------
# Headscale VPS - Terraform
# ------------------------------------------------------------------------------

headscale:
	@test -f .env || (echo "Error: .env not found. Run: make setup" && exit 1)
	@bash -c 'source .env && test -n "$$HCLOUD_TOKEN" || (echo "HCLOUD_TOKEN not set" && exit 1)'
	@bash -c 'source .env && test -n "$$SSH_PUBLIC_KEY_FILE" || (echo "SSH_PUBLIC_KEY_FILE not set" && exit 1)'
	@bash -c 'source .env && test -n "$$HEADSCALE_DOMAIN" || (echo "HEADSCALE_DOMAIN not set" && exit 1)'
	@bash -c 'source .env && test -n "$$HEADSCALE_BASE_DOMAIN" || (echo "HEADSCALE_BASE_DOMAIN not set" && exit 1)'
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
	@echo "VPS created. Save this to .env:"
	@echo ""
	@bash -c 'cd terraform/headscale-vps && echo "HEADSCALE_IP=$$(terraform output -raw ipv4_address)"'
	@echo ""
	@echo "Then run: make headscale-init"
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

headscale-init: venv
	@test -f ansible/inventory.yml || (echo "Run 'make headscale' first" && exit 1)
	@echo "Initializing Headscale VPS..."
	@bash -c 'source .venv/bin/activate && cd ansible && ansible-playbook headscale.yaml'
	@echo ""
	@echo "=========================================="
	@echo "Done! Save the HEADSCALE_AUTHKEY to .env"
	@echo "=========================================="

headscale-configure: venv
	@test -f ansible/inventory.yml || (echo "Run 'make headscale' first" && exit 1)
	@echo "Configuring Headscale VPS..."
	@bash -c 'source .venv/bin/activate && source .env && \
		test -n "$$HEADSCALE_USER" || (echo "HEADSCALE_USER not set" && exit 1) && \
		cd ansible && \
		ansible-playbook headscale.yaml -e "ansible_user=$${HEADSCALE_USER:-admin}"

headscale-ssh:
	@test -f .env || (echo "Error: .env not found" && exit 1)
	@bash -c 'source .env && \
		HEADSCALE_IP=$$(cd terraform/headscale-vps && terraform output -raw ipv4_address) && \
		ssh -i $${SSH_PUBLIC_KEY_FILE%.pub} $${HEADSCALE_USER:-mkultra}@$$HEADSCALE_IP'