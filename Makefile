# ==============================================================================
# H-Kube Makefile
# ==============================================================================

.PHONY: help setup venv anchor anchor-destroy anchor-init anchor-configure anchor-ssh cp cp-destroy cp-init cp-configure cp-ssh join-mesh bootstrap

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
	@echo ""
	@echo "  Control Plane VPS:"
	@echo "    make cp                 - Create Control Plane VPS (Terraform)"
	@echo "    make cp-destroy         - Destroy Control Plane VPS"
	@echo "    make cp-init            - First-time VPS config (as root)"
	@echo "    make cp-configure       - Re-run VPS config (as admin user)"
	@echo "    make cp-ssh             - SSH into Control Plane VPS"
	@echo ""
	@echo "  Node Bootstrap (run on node itself):"
	@echo "    make join-mesh          - Join Tailscale mesh"
	@echo "    make bootstrap          - Bootstrap node (prompts for options)"

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
	@echo "Anchor VPS created."
	@echo ""
	@echo "Run: make anchor-init"
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
# Control Plane VPS - Terraform
# ------------------------------------------------------------------------------

cp:
	@test -f .env || (echo "Error: .env not found. Run: make setup" && exit 1)
	@bash -c 'source .env && test -n "$$HCLOUD_TOKEN" || (echo "HCLOUD_TOKEN not set" && exit 1)'
	@bash -c 'source .env && test -n "$$SSH_PUBLIC_KEY_FILE" || (echo "SSH_PUBLIC_KEY_FILE not set" && exit 1)'
	@echo "Creating Control Plane VPS..."
	@bash -c 'source .env && \
		export TF_VAR_hcloud_token="$$HCLOUD_TOKEN" && \
		export TF_VAR_ssh_public_key="$$(cat $$SSH_PUBLIC_KEY_FILE)" && \
		cd terraform/control-plane && \
		terraform init && \
		terraform apply'
	@./scripts/generate-inventory.sh
	@echo ""
	@echo "=========================================="
	@echo "Control Plane VPS created."
	@echo ""
	@echo "Run: make cp-init"
	@echo "=========================================="

cp-destroy:
	@test -f .env || (echo "Error: .env not found" && exit 1)
	@bash -c 'source .env && \
		export TF_VAR_hcloud_token="$$HCLOUD_TOKEN" && \
		export TF_VAR_ssh_public_key="$$(cat $$SSH_PUBLIC_KEY_FILE)" && \
		cd terraform/control-plane && \
		terraform destroy'

# ------------------------------------------------------------------------------
# Control Plane VPS - Ansible
# ------------------------------------------------------------------------------

cp-init: venv
	@test -f ansible/inventory.yml || (echo "Run 'make cp' first" && exit 1)
	@echo "Initializing Control Plane VPS..."
	@bash -c 'source .venv/bin/activate && cd ansible && ansible-playbook control-plane.yaml'
	@echo ""
	@echo "=========================================="
	@echo "Control Plane initialized."
	@echo "=========================================="

cp-configure: venv
	@test -f ansible/inventory.yml || (echo "Run 'make cp' first" && exit 1)
	@echo "Configuring Control Plane VPS..."
	@bash -c 'source .venv/bin/activate && source .env && \
		test -n "$$ANCHOR_USER" || (echo "ANCHOR_USER not set" && exit 1) && \
		cd ansible && \
		ansible-playbook control-plane.yaml -e "ansible_user=$$ANCHOR_USER"'

cp-ssh:
	@test -f .env || (echo "Error: .env not found" && exit 1)
	@bash -c 'source .env && \
		CP_IP=$$(cd terraform/control-plane && terraform output -raw ipv4_address) && \
		ssh -i $${SSH_PUBLIC_KEY_FILE%.pub} root@$$CP_IP'

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

bootstrap: join-mesh
	@echo "Installing Ansible..."
	@which ansible-playbook > /dev/null || (sudo apt update && sudo apt install -y ansible)
	@bash -c '\
		while true; do \
			read -p "Server or worker? [s/w]: " role_choice; \
			case "$$role_choice" in \
				[sS]) k3s_role="server"; role_display="server"; break;; \
				[wW]) k3s_role="agent"; role_display="worker"; break;; \
				*) echo "Invalid input. Enter s or w.";; \
			esac; \
		done; \
		\
		while true; do \
			read -p "Fresh system (run hardening)? [y/n]: " fresh_choice; \
			case "$$fresh_choice" in \
				[yY]) include_base="true"; base_display="yes"; break;; \
				[nN]) include_base="false"; base_display="no"; break;; \
				*) echo "Invalid input. Enter y or n.";; \
			esac; \
		done; \
		\
		source .env; \
		if [ "$$k3s_role" = "agent" ] && [ -z "$$K3S_TOKEN" ]; then \
			echo "Error: K3S_TOKEN not set in .env (required for worker mode)" && exit 1; \
		fi; \
		\
		echo ""; \
		echo "Will bootstrap as: $$role_display"; \
		echo "Include hardening: $$base_display"; \
		echo ""; \
		while true; do \
			read -p "Continue? [y/n]: " confirm; \
			case "$$confirm" in \
				[yY]) break;; \
				[nN]) echo "Aborted."; exit 0;; \
				*) echo "Invalid input. Enter y or n.";; \
			esac; \
		done; \
		\
		echo ""; \
		echo "Bootstrapping..."; \
		set -a && source .env && set +a && \
		cd ansible && ansible-playbook bootstrap.yaml -e "k3s_role=$$k3s_role include_base=$$include_base"'