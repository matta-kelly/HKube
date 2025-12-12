# H-Kube

GitOps-managed K3s cluster with Cilium, Flux, and SOPS encryption.

---

## Overview

- **What We've Built**
  - Ansible bootstrap runs once, takes bare Ubuntu to functional GitOps cluster

- **base role**
  - Create admin user
  - Harden SSH (disable root, key-only)
  - Install fail2ban, ufw, unattended-upgrades
  - Configure firewall

- **common role**
  - Install packages
  - Disable swap
  - Configure sysctl

- **k3s role**
  - Install k3s (no flannel, no traefik)
  - Fetch kubeconfig to your laptop

- **cilium role**
  - Install Helm
  - Deploy Cilium CNI (pods can now talk)

- **flux role**
  - Install flux CLI, sops, age
  - Generate age keypair
  - Update `.sops.yaml` with public key
  - Create sops-age secret in cluster
  - Bootstrap Flux (connects to your GitHub repo)

After Ansible completes, Flux watches `clusters/` and takes over.

---

## Components

- **k3s**
  - Installed by: Ansible
  - Purpose: Lightweight Kubernetes runtime

- **Cilium**
  - Installed by: Ansible
  - Purpose: Pod networking (CNI), replaces flannel + kube-proxy

- **Flux**
  - Installed by: Ansible
  - Purpose: GitOps — syncs cluster state from Git

- **Traefik**
  - Installed by: Flux
  - Purpose: Ingress — routes traffic into cluster

- **CloudNativePG**
  - Installed by: Flux
  - Purpose: Postgres operator — manages DB clusters

- **SeaweedFS**
  - Installed by: Flux (TODO)
  - Purpose: Distributed storage with S3 API

- **Headscale**
  - Installed by: Terraform + Ansible (separate VPS)
  - Purpose: Mesh networking control plane

---

## Prerequisites

- **Local machine**
  - Ansible: `pip install ansible ansible-core`
  - Ansible collections: `ansible-galaxy collection install kubernetes.core community.general ansible.posix`
  - Terraform: [install guide](https://developer.hashicorp.com/terraform/downloads)
  - SOPS: [install guide](https://github.com/getsops/sops)
  - direnv (optional): [install guide](https://direnv.net)

- **Home server**
  - Ubuntu 22.04 or 24.04 LTS
  - SSH access with sudo
  - 4GB+ RAM, 2+ CPU cores

- **Hetzner Cloud** (for Headscale VPS)
  - Account at [console.hetzner.cloud](https://console.hetzner.cloud)
  - API token with read/write access

---

## Setup

**Create `.env` in repo root:**
```bash
# ==============================================================================
# H-Kube Environment
# ==============================================================================

# ------------------------------------------------------------------------------
# Hetzner Cloud
# ------------------------------------------------------------------------------
HCLOUD_TOKEN=""

# ------------------------------------------------------------------------------
# SSH
# ------------------------------------------------------------------------------
SSH_PUBLIC_KEY_FILE="$HOME/.ssh/id_ed25519_hetzner.pub"

# ------------------------------------------------------------------------------
# Headscale VPS (set HEADSCALE_IP after 'make headscale')
# ------------------------------------------------------------------------------
HEADSCALE_IP=""
HEADSCALE_USER="mkultra"

# ------------------------------------------------------------------------------
# Home Server
# ------------------------------------------------------------------------------
SERVER_IP=""
SERVER_USER="mkultra"

# ------------------------------------------------------------------------------
# GitHub
# ------------------------------------------------------------------------------
GITHUB_USER=""
GITHUB_TOKEN=""
GITHUB_REPO="h-kube"
GITHUB_BRANCH="main"
```

**If using direnv:**
```bash
direnv allow
```

---

## Commands
```bash
make help                 # Show all commands

# Headscale VPS
make headscale            # Create VPS (Terraform)
make headscale-init       # First-time setup (as root)
make headscale-configure  # Re-configure (as HEADSCALE_USER)
make headscale-ssh        # SSH into VPS
make headscale-destroy    # Destroy VPS

# Home Server
make bootstrap            # Bootstrap k3s cluster
make ansible-ping         # Test connectivity

# Secrets
make encrypt FILE=...     # Encrypt with SOPS
make decrypt FILE=...     # Decrypt with SOPS
```

---

## Quick Start: Headscale VPS
```bash
# 1. Generate SSH key (if needed)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_hetzner -C "h-kube"

# 2. Get Hetzner API token
#    - Go to console.hetzner.cloud
#    - Create project (e.g., "h-kube")
#    - Security → API Tokens → Generate API Token (Read & Write)

# 3. Edit .env
HCLOUD_TOKEN="your-token"
SSH_PUBLIC_KEY_FILE="$HOME/.ssh/id_ed25519_hetzner.pub"
HEADSCALE_USER="mkultra"

# 4. Create VPS
make headscale
# → Note the ipv4_address from output

# 5. Add IP to .env
HEADSCALE_IP="49.12.xxx.xxx"

# 6. Initialize VPS (first run, as root)
make headscale-init
# → Creates admin user
# → Hardens SSH (disables root login)
# → Installs fail2ban, ufw, auto-updates

# 7. Add to ~/.ssh/config (printed by command above)
Host headscale
  HostName 49.12.xxx.xxx
  User mkultra
  IdentityFile ~/.ssh/id_ed25519_hetzner
  IdentitiesOnly yes

# 8. Test SSH
ssh headscale
```

---

## Quick Start: Home K3s Cluster
```bash
# 1. Edit .env
SERVER_IP="192.168.1.100"
SERVER_USER="mkultra"
GITHUB_USER="your-username"
GITHUB_TOKEN="ghp_xxxxx"

# 2. Bootstrap cluster
make bootstrap
# → Runs base, common, k3s, cilium, flux roles
# → Flux connects to GitHub repo

# 3. Flux takes over
# → Watches clusters/ directory
# → Deploys Traefik, CloudNativePG, etc.
```

---

## Encrypting Secrets
```bash
# Create plaintext secret
cat > clusters/apps/vaultwarden/secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: vaultwarden
  namespace: vaultwarden
stringData:
  ADMIN_TOKEN: "your-secret-token"
EOF

# Encrypt it
make encrypt FILE=clusters/apps/vaultwarden/secret.yaml

# Commit encrypted file (safe to push)
git add clusters/apps/vaultwarden/secret.yaml
git commit -m "Add vaultwarden secret"
git push

# Flux decrypts in-cluster automatically
```

---

## Variables and Secrets

- **Environment variables (in `.env`, gitignored)**
  - `HCLOUD_TOKEN` — Hetzner API token
  - `SSH_PUBLIC_KEY_FILE` — path to SSH public key
  - `HEADSCALE_IP` — Headscale VPS IP (set after creation)
  - `HEADSCALE_USER` — admin user on Headscale VPS
  - `SERVER_IP` — home server IP address
  - `SERVER_USER` — admin user on home server
  - `GITHUB_USER` — your GitHub username
  - `GITHUB_TOKEN` — GitHub personal access token
  - `GITHUB_REPO` — repository name (default: h-kube)
  - `GITHUB_BRANCH` — branch name (default: main)

- **Helm values (in release.yaml files)**
  - `clusters/infrastructure/traefik/release.yaml`
  - `clusters/infrastructure/cloudnative-pg/release.yaml`

- **App secrets (encrypted with SOPS, committed)**
  - Location: `clusters/apps/<app>/secret.yaml`
  - Encrypted locally with `sops` CLI
  - Decrypted in-cluster by Flux using age key

---

## Structure
```
h-kube/
├── .env                       # Your environment (gitignored)
├── .envrc                     # direnv auto-loader
├── .gitignore
├── .sops.yaml                 # SOPS config (age key auto-generated)
├── Makefile                   # Commands
├── README.md
│
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.yaml         # Ansible variables
│   ├── site.yaml              # Home server playbook
│   ├── headscale.yaml         # Headscale VPS playbook
│   └── roles/
│       ├── base/              # Server hardening (all servers)
│       │   ├── tasks/main.yaml
│       │   └── handlers/main.yaml
│       ├── common/            # K3s prep
│       │   └── tasks/main.yaml
│       ├── k3s/
│       │   └── tasks/main.yaml
│       ├── cilium/
│       │   ├── tasks/main.yaml
│       │   └── templates/values.yaml.j2
│       └── flux/
│           ├── tasks/main.yaml
│           └── templates/sops.yaml.j2
│
├── clusters/
│   ├── kustomization.yaml
│   ├── flux-system/
│   │   └── kustomization.yaml
│   ├── infrastructure/
│   │   ├── kustomization.yaml
│   │   ├── cilium/
│   │   │   └── kustomization.yaml
│   │   ├── cloudnative-pg/
│   │   │   ├── kustomization.yaml
│   │   │   ├── namespace.yaml
│   │   │   ├── repository.yaml
│   │   │   └── release.yaml
│   │   ├── seaweedfs/
│   │   │   └── kustomization.yaml
│   │   └── traefik/
│   │       ├── kustomization.yaml
│   │       ├── repository.yaml
│   │       └── release.yaml
│   └── apps/
│       ├── kustomization.yaml
│       ├── postgres-cluster/
│       │   └── kustomization.yaml
│       ├── vaultwarden/
│       │   └── kustomization.yaml
│       └── immich/
│           └── kustomization.yaml
│
└── terraform/
    ├── .gitignore
    └── headscale-vps/
        ├── .gitignore
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

---

## Disaster Recovery
```bash
# Fresh Ubuntu server — full restore from Git

# 1. Clone repo
git clone git@github.com:$GITHUB_USER/h-kube.git
cd h-kube

# 2. Create .env with your values

# 3. Bootstrap
make bootstrap

# 4. Flux restores all cluster state from Git
```

---

## Future Hybrid Structure

- **Why separate cluster dirs (later)?**
  - Some workloads are location-specific:
    - Immich → home (local photo storage)
    - Public API → Hetzner (low latency for users)
    - Vaultwarden → either (replicated)
  - `base/` holds shared infrastructure
  - `home/` and `hetzner/` overlay site-specific apps
  - Cilium Cluster Mesh + SeaweedFS make data layer seamless

---

## Current State

- Single-node foundation
- Headscale VPS for mesh networking
- Ready to expand

