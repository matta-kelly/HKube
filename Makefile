# ==============================================================================
# H-Kube Makefile
# ==============================================================================

.PHONY: help setup generate venv anchor anchor-destroy anchor-init anchor-configure anchor-ssh cp cp-destroy cp-init cp-configure cp-ssh join-mesh bootstrap bootstrap-node cluster-status network-status node-configure

help:
	@echo "H-Kube Commands:"
	@echo ""
	@echo "  Setup & Generate:"
	@echo "    make setup              - Initial setup (creates config/)"
	@echo "    make generate           - Generate inventory from config/"
	@echo ""
	@echo "  Document State:"
	@echo "    make cluster-status     - Document K3s cluster state"
	@echo "    make network-status     - Document Tailscale mesh state"
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
	@echo "  Node Bootstrap:"
	@echo "    make bootstrap-node NODE=<name>  - Bootstrap node remotely (from workstation)"
	@echo "    make node-configure NODE=<name>  - Re-configure node remotely"
	@echo ""
	@echo "  Local Bootstrap (run ON the node):"
	@echo "    make join-mesh NODE_HOSTNAME=<name>  - Join Tailscale mesh"
	@echo "    make bootstrap NODE_HOSTNAME=<name>  - Full local bootstrap"

# ------------------------------------------------------------------------------
# Document State
# ------------------------------------------------------------------------------

cluster-status:
	@./scripts/document-cluster.sh

network-status:
	@PROJECT_ROOT="$(CURDIR)" ./scripts/document-network.sh

# ------------------------------------------------------------------------------
# Initial Setup
# ------------------------------------------------------------------------------

setup:
	@echo "Setting up h-kube..."
	@mkdir -p config
	@test -f config/config.yaml || cp config.example/config.yaml config/config.yaml
	@test -f config/secrets.env || cp config.example/secrets.env config/secrets.env
	@echo ""
	@echo "Done. Edit config/config.yaml and config/secrets.env, then run: make generate"

# ------------------------------------------------------------------------------
# Generate Inventory
# ------------------------------------------------------------------------------

generate: venv
	@test -f config/config.yaml || (echo "Error: config/config.yaml not found. Run: make setup" && exit 1)
	@test -f config/secrets.env || (echo "Error: config/secrets.env not found. Run: make setup" && exit 1)
	@echo "Generating inventory..."
	@bash -c 'source .venv/bin/activate && python scripts/generate.py'
	@echo "Done. Generated files in generated/"

# ------------------------------------------------------------------------------
# Python Virtual Environment
# ------------------------------------------------------------------------------

venv:
	@if [ ! -d ".venv" ]; then \
		echo "Creating Python virtual environment..."; \
		python3 -m venv .venv; \
		. .venv/bin/activate && pip install --upgrade pip && pip install ansible pyyaml; \
		echo "Virtual environment created."; \
	fi

# ------------------------------------------------------------------------------
# Anchor VPS - Terraform
# ------------------------------------------------------------------------------

anchor: venv
	@test -f config/secrets.env || (echo "Error: config/secrets.env not found. Run: make setup" && exit 1)
	@test -f config/config.yaml || (echo "Error: config/config.yaml not found. Run: make setup" && exit 1)
	@bash -c 'source config/secrets.env && test -n "$$HCLOUD_TOKEN" || (echo "HCLOUD_TOKEN not set in config/secrets.env" && exit 1)'
	@echo "Creating Anchor VPS..."
	@bash -c 'source .venv/bin/activate && source config/secrets.env && \
		SSH_KEY_FILE=$$(python -c "import yaml; c=yaml.safe_load(open(\"config/config.yaml\")); import os; print(os.path.expanduser(c[\"ssh_keys\"][\"hetzner\"]))") && \
		export TF_VAR_hcloud_token="$$HCLOUD_TOKEN" && \
		export TF_VAR_ssh_public_key="$$(cat $$SSH_KEY_FILE.pub)" && \
		cd terraform/anchor-vps && \
		terraform init && \
		terraform apply'
	@$(MAKE) generate
	@echo ""
	@echo "=========================================="
	@echo "Anchor VPS created. Run: make anchor-init"
	@echo "=========================================="

anchor-destroy: venv
	@test -f config/secrets.env || (echo "Error: config/secrets.env not found" && exit 1)
	@bash -c 'source .venv/bin/activate && source config/secrets.env && \
		SSH_KEY_FILE=$$(python -c "import yaml; c=yaml.safe_load(open(\"config/config.yaml\")); import os; print(os.path.expanduser(c[\"ssh_keys\"][\"hetzner\"]))") && \
		export TF_VAR_hcloud_token="$$HCLOUD_TOKEN" && \
		export TF_VAR_ssh_public_key="$$(cat $$SSH_KEY_FILE.pub)" && \
		cd terraform/anchor-vps && \
		terraform destroy'

# ------------------------------------------------------------------------------
# Anchor VPS - Ansible
# ------------------------------------------------------------------------------

anchor-init: generate
	@echo "Initializing Anchor VPS (first run as root)..."
	@bash -c 'source .venv/bin/activate && set -a && source config/secrets.env && set +a && cd ansible && ansible-playbook -i ../generated/inventory.yml anchor.yaml -e ansible_user=root'
	@echo ""
	@echo "=========================================="
	@echo "Done! Save the HEADSCALE_AUTHKEY to config/secrets.env"
	@echo "=========================================="

anchor-configure: generate
	@echo "Configuring Anchor VPS (as mkultra)..."
	@bash -c 'source .venv/bin/activate && set -a && source config/secrets.env && set +a && cd ansible && ansible-playbook -i ../generated/inventory.yml anchor.yaml -e ansible_user=mkultra'

anchor-ssh:
	@bash -c 'ANCHOR_IP=$$(cd terraform/anchor-vps && terraform output -raw ipv4_address 2>/dev/null) && \
		if [ -z "$$ANCHOR_IP" ]; then echo "Error: Could not get anchor IP from Terraform"; exit 1; fi && \
		ssh mkultra@$$ANCHOR_IP'

# ------------------------------------------------------------------------------
# Control Plane VPS - Terraform
# ------------------------------------------------------------------------------

cp: venv
	@test -f config/secrets.env || (echo "Error: config/secrets.env not found. Run: make setup" && exit 1)
	@test -f config/config.yaml || (echo "Error: config/config.yaml not found. Run: make setup" && exit 1)
	@bash -c 'source config/secrets.env && test -n "$$HCLOUD_TOKEN" || (echo "HCLOUD_TOKEN not set in config/secrets.env" && exit 1)'
	@echo "Creating Control Plane VPS..."
	@bash -c 'source .venv/bin/activate && source config/secrets.env && \
		SSH_KEY_FILE=$$(python -c "import yaml; c=yaml.safe_load(open(\"config/config.yaml\")); import os; print(os.path.expanduser(c[\"ssh_keys\"][\"hetzner\"]))") && \
		export TF_VAR_hcloud_token="$$HCLOUD_TOKEN" && \
		export TF_VAR_ssh_public_key="$$(cat $$SSH_KEY_FILE.pub)" && \
		cd terraform/control-plane && \
		terraform init && \
		terraform apply'
	@$(MAKE) generate
	@echo ""
	@echo "=========================================="
	@echo "Control Plane VPS created. Run: make cp-init"
	@echo "=========================================="

cp-destroy: venv
	@test -f config/secrets.env || (echo "Error: config/secrets.env not found" && exit 1)
	@bash -c 'source .venv/bin/activate && source config/secrets.env && \
		SSH_KEY_FILE=$$(python -c "import yaml; c=yaml.safe_load(open(\"config/config.yaml\")); import os; print(os.path.expanduser(c[\"ssh_keys\"][\"hetzner\"]))") && \
		export TF_VAR_hcloud_token="$$HCLOUD_TOKEN" && \
		export TF_VAR_ssh_public_key="$$(cat $$SSH_KEY_FILE.pub)" && \
		cd terraform/control-plane && \
		terraform destroy'

# ------------------------------------------------------------------------------
# Control Plane VPS - Ansible
# ------------------------------------------------------------------------------

cp-init: generate
	@echo "Initializing Control Plane VPS (first run as root)..."
	@bash -c 'source .venv/bin/activate && set -a && source config/secrets.env && set +a && cd ansible && ansible-playbook -i ../generated/inventory.yml control-plane.yaml -e ansible_user=root'
	@echo ""
	@echo "=========================================="
	@echo "Control Plane initialized."
	@echo "=========================================="

cp-configure: generate
	@echo "Configuring Control Plane VPS..."
	@bash -c 'source .venv/bin/activate && set -a && source config/secrets.env && set +a && cd ansible && ansible-playbook -i ../generated/inventory.yml control-plane.yaml'

cp-ssh:
	@bash -c 'CP_IP=$$(cd terraform/control-plane && terraform output -raw ipv4_address 2>/dev/null) && \
		if [ -z "$$CP_IP" ]; then echo "Error: Could not get CP IP from Terraform"; exit 1; fi && \
		ssh mkultra@$$CP_IP'

# ------------------------------------------------------------------------------
# Node Bootstrap (run on the node itself)
# ------------------------------------------------------------------------------

join-mesh:
	@test -f config/secrets.env || (echo "Error: config/secrets.env not found" && exit 1)
	@bash -c 'source config/secrets.env && test -n "$$HEADSCALE_AUTHKEY" || (echo "HEADSCALE_AUTHKEY not set in config/secrets.env" && exit 1)'
	@test -n "$(NODE_HOSTNAME)" || (echo "Error: NODE_HOSTNAME not set. Usage: make join-mesh NODE_HOSTNAME=mynode" && exit 1)
	@echo "Installing Tailscale..."
	@which tailscale > /dev/null || curl -fsSL https://tailscale.com/install.sh | sh
	@echo "Checking current state..."
	@bash -c 'if tailscale status > /dev/null 2>&1; then \
		echo "Already connected, logging out to re-register..."; \
		sudo tailscale logout; \
	fi'
	@echo "Joining mesh as $(NODE_HOSTNAME)..."
	@bash -c 'source config/secrets.env && \
		DOMAIN=$$(grep -E "^[[:space:]]*domain:" config/config.yaml | head -1 | sed "s/.*domain:[[:space:]]*//") && \
		sudo tailscale up --login-server https://headscale.$$DOMAIN --authkey $$HEADSCALE_AUTHKEY --hostname $(NODE_HOSTNAME)'
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
		source config/secrets.env; \
		if [ "$$k3s_role" = "agent" ]; then \
			if [ -z "$$K3S_TOKEN" ]; then \
				echo "Error: K3S_TOKEN not set in config/secrets.env (required for worker)" && exit 1; \
			fi; \
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
		set -a && source config/secrets.env && set +a && \
		cd ansible && ansible-playbook bootstrap.yaml -e "k3s_role=$$k3s_role include_base=$$include_base"'

# ------------------------------------------------------------------------------
# Remote Node Bootstrap (run from workstation)
# ------------------------------------------------------------------------------

bootstrap-node: generate
	@test -n "$(NODE)" || (echo "Usage: make bootstrap-node NODE=<node-name>" && exit 1)
	@echo "Bootstrapping $(NODE) remotely..."
	@echo "(Enter sudo password when prompted - only needed for first run)"
	@bash -c 'source .venv/bin/activate && set -a && source config/secrets.env && set +a && \
		cd ansible && ansible-playbook -i ../generated/inventory.yml node.yaml --limit $(NODE) --ask-become-pass'

node-configure: generate
	@test -n "$(NODE)" || (echo "Usage: make node-configure NODE=<node-name>" && exit 1)
	@echo "Configuring $(NODE)..."
	@bash -c 'source .venv/bin/activate && set -a && source config/secrets.env && set +a && \
		cd ansible && ansible-playbook -i ../generated/inventory.yml node.yaml --limit $(NODE)'