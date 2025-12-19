# ==============================================================================
# H-Kube Makefile
# ==============================================================================

.PHONY: help setup venv anchor anchor-destroy anchor-init anchor-configure anchor-ssh

help:
	@echo "H-Kube Commands:"
	@echo ""
	@echo "  Setup:"
	@echo "    make setup              - Initial setup (creates .env)"
	@echo ""
	@echo "  Anchor VPS:"
	@echo "    make anchor             - Create Anchor VPS (Terraform)"
	@echo "    make anchor-destroy     - Destroy Anchor VPS"
	@echo "    make anchor-init        - First-time VPS config (as root)"
	@echo "    make anchor-configure   - Re-run VPS config (as admin user)"
	@echo "    make anchor-ssh         - SSH into Anchor VPS"

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
	@echo "Done. Edit .env with your values, then run: make anchor"

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
# Anchor VPS - Terraform
# ------------------------------------------------------------------------------

anchor:
	@test -f .env || (echo "Error: .env not found. Run: make setup" && exit 1)
	@bash -c 'source .env && test -n "$$HCLOUD_TOKEN" || (echo "HCLOUD_TOKEN not set" && exit 1)'
	@bash -c 'source .env && test -n "$$SSH_PUBLIC_KEY_FILE" || (echo "SSH_PUBLIC_KEY_FILE not set" && exit 1)'
	@bash -c 'source .env && test -n "$$HEADSCALE_DOMAIN" || (echo "HEADSCALE_DOMAIN not set" && exit 1)'
	@bash -c 'source .env && test -n "$$HEADSCALE_BASE_DOMAIN" || (echo "HEADSCALE_BASE_DOMAIN not set" && exit 1)'
	@echo "Creating Anchor VPS..."
	@bash -c 'source .env && \
		export TF_VAR_hcloud_token="$$HCLOUD_TOKEN" && \
		export TF_VAR_ssh_public_key="$$(cat $$SSH_PUBLIC_KEY_FILE)" && \
		cd terraform/anchor-vps && \
		terraform init && \
		terraform apply'
	@./scripts/generate-inventory.sh
	@echo ""
	@echo "=========================================="
	@echo "VPS created. Save this to .env:"
	@echo ""
	@bash -c 'cd terraform/anchor-vps && echo "ANCHOR_IP=$$(terraform output -raw ipv4_address)"'
	@echo ""
	@echo "Then run: make anchor-init"
	@echo "=========================================="

anchor-destroy:
	@test -f .env || (echo "Error: .env not found" && exit 1)
	@bash -c 'source .env && \
		export TF_VAR_hcloud_token="$$HCLOUD_TOKEN" && \
		export TF_VAR_ssh_public_key="$$(cat $$SSH_PUBLIC_KEY_FILE)" && \
		cd terraform/anchor-vps && \
		terraform destroy'

# ------------------------------------------------------------------------------
# Anchor VPS - Ansible
# ------------------------------------------------------------------------------

anchor-init: venv
	@test -f ansible/inventory.yml || (echo "Run 'make anchor' first" && exit 1)
	@echo "Initializing Anchor VPS..."
	@bash -c 'source .venv/bin/activate && cd ansible && ansible-playbook anchor.yaml'
	@echo ""
	@echo "=========================================="
	@echo "Done! Save the HEADSCALE_AUTHKEY to .env"
	@echo "=========================================="

anchor-configure: venv
	@test -f ansible/inventory.yml || (echo "Run 'make anchor' first" && exit 1)
	@echo "Configuring Anchor VPS..."
	@bash -c 'source .venv/bin/activate && source .env && \
		test -n "$$ANCHOR_USER" || (echo "ANCHOR_USER not set" && exit 1) && \
		cd ansible && \
		ansible-playbook anchor.yaml -e "ansible_user=$$ANCHOR_USER"'

anchor-ssh:
	@test -f .env || (echo "Error: .env not found" && exit 1)
	@bash -c 'source .env && \
		ANCHOR_IP=$$(cd terraform/anchor-vps && terraform output -raw ipv4_address) && \
		ssh -i $${SSH_PUBLIC_KEY_FILE%.pub} $${ANCHOR_USER:-mkultra}@$$ANCHOR_IP'


# ------------------------------------------------------------------------------
# Node Bootstrap (run on the node itself)
# ------------------------------------------------------------------------------

join-mesh:
	@test -f .env || (echo "Run 'make setup' first" && exit 1)
	@bash -c 'source .env && test -n "$$HEADSCALE_AUTHKEY" || (echo "HEADSCALE_AUTHKEY not set" && exit 1)'
	@bash -c 'source .env && test -n "$$NODE_HOSTNAME" || (echo "NODE_HOSTNAME not set" && exit 1)'
	@echo "Installing Tailscale..."
	@which tailscale > /dev/null || curl -fsSL https://tailscale.com/install.sh | sh
	@echo "Checking current state..."
	@bash -c 'if tailscale status > /dev/null 2>&1; then \
		echo "Already connected, logging out to re-register..."; \
		sudo tailscale logout; \
	fi'
	@echo "Joining mesh..."
	@bash -c 'source .env && sudo tailscale up --login-server https://$$HEADSCALE_DOMAIN --authkey $$HEADSCALE_AUTHKEY --hostname $$NODE_HOSTNAME'
	@echo "Verifying..."
	@tailscale status