# H-Kube

Hybrid Kubernetes cluster spanning cloud VPS and home servers, connected via Tailscale mesh.

## Architecture

```
                    Internet
                        |
                +-------+-------+
                |  Anchor VPS   |
                |  (Headscale)  |
                +-------+-------+
                        | Tailscale Mesh
        +---------------+---------------+
        |               |               |
+-------+-------+ +-----+-----+ +-------+-------+
| Cloud CP VPS  | | gpa-server| | monkeybusiness|
| (k3s server)  | | (k3s agent)| | (k3s agent)  |
| location:cloud| |location:home| |location:home |
+---------------+ +-----------+ +---------------+
```

**Components:**
- **Anchor VPS** - Headscale coordination server
- **Cloud Control Plane** - k3s server with public IP (runs Traefik ingress)
- **Home Workers** - k3s agents with local storage
- **CNI** - Flannel with VXLAN over Tailscale
- **GitOps** - Flux CD syncing from this repo

## Quick Start

### 1. Setup
```bash
git clone git@github.com:matta-kelly/HKube.git
cd HKube
make setup          # Creates config/ from templates
# Edit config/config.yaml and config/secrets.env
make generate       # Generates inventory
```

### 2. Deploy Infrastructure
```bash
# Anchor (Headscale)
make anchor && make anchor-init
# Save HEADSCALE_AUTHKEY to config/secrets.env

# Control Plane
make cp && make cp-init
# Save K3S_TOKEN to config/secrets.env
```

### 3. Add Worker Nodes
```bash
# Remote bootstrap (from workstation)
make bootstrap-node NODE=gpa-server

# Or local bootstrap (on the node itself)
make join-mesh NODE_HOSTNAME=mynode
make bootstrap NODE_HOSTNAME=mynode
```

## Configuration

All configuration lives in `config/`:

```
config/
├── config.yaml     # Node definitions, labels, SSH keys
└── secrets.env     # Tokens and sensitive values
```

### config.yaml (Source of Truth)

Defines nodes, their roles, labels, and storage capabilities:

```yaml
nodes:
  gpa-server:
    type: home
    role: k3s-agent
    tailscale_ip: 100.64.0.3
    ssh_key: gpa_server
    labels:
      location: home
      room: office
    storage:
      nvme: true
      bulk: true
```

### secrets.env

```bash
HCLOUD_TOKEN=""           # Hetzner API
HEADSCALE_AUTHKEY=""      # From make anchor-init
K3S_TOKEN=""              # From make cp-init
GITHUB_TOKEN=""           # For Flux bootstrap
```

## Commands

```bash
make help              # Show all commands

# Generate & Document
make generate          # Generate inventory from config
make cluster-status    # Document live cluster state
make network-status    # Document Tailscale mesh

# Infrastructure
make anchor            # Create Anchor VPS
make anchor-init       # Configure Headscale
make cp                # Create Control Plane VPS
make cp-init           # Configure k3s server

# Node Management
make bootstrap-node NODE=<name>   # Bootstrap node remotely
make node-configure NODE=<name>   # Reconfigure node
```

## Node Labels

Labels are defined in `config/config.yaml` and applied during bootstrap:

| Label | Purpose | Values |
|-------|---------|--------|
| `node.h-kube.io/role` | Node role | `server`, `agent` |
| `node.h-kube.io/location` | Physical location | `cloud`, `home` |
| `storage.h-kube.io/bulk` | Has bulk HDD | `true`, `false` |
| `storage.h-kube.io/nvme` | Has fast NVMe | `true`, `false` |

Use labels in workload nodeSelectors:
```yaml
nodeSelector:
  storage.h-kube.io/bulk: "true"    # Runs on nodes with bulk storage
  node.h-kube.io/location: "home"   # Runs on home nodes
```

## Project Structure

```
h-kube/
├── config/                 # SOURCE (gitignored)
│   ├── config.yaml         # Node definitions
│   └── secrets.env         # Tokens/secrets
├── config.example/         # Templates (committed)
├── generated/              # GENERATED (gitignored)
│   ├── inventory.yml       # Ansible inventory
│   ├── cluster-config.yaml # Cluster state doc
│   └── network-status.yaml # Mesh state doc
├── ansible/
│   ├── roles/
│   │   ├── base/           # Security hardening
│   │   ├── tailscale/      # Mesh client
│   │   ├── common/         # K8s prerequisites
│   │   ├── k3s/            # K3s install
│   │   └── flux/           # GitOps setup
│   └── bootstrap.yaml      # Node bootstrap playbook
├── cluster/                # GitOps manifests (Flux syncs)
│   ├── cluster-vars.yaml   # Flux variables
│   └── infrastructure/     # Apps and services
├── scripts/
│   ├── generate.py         # Config -> Inventory
│   ├── document-cluster.sh # Cluster state
│   └── document-network.sh # Network state
└── terraform/
    ├── anchor-vps/
    └── control-plane/
```

## Workflow

1. **Configure** - Edit `config/config.yaml`
2. **Generate** - `make generate` creates inventory
3. **Bootstrap** - `make bootstrap-node NODE=<name>` sets up node
4. **Document** - `make cluster-status` captures state

Problems encountered become documentation updates.

## Disaster Recovery

All infrastructure is code. Backup only `config/secrets.env` values.

```bash
# Anchor gone?
make anchor && make anchor-init
# Update HEADSCALE_AUTHKEY, reconnect devices

# Control plane gone?
make cp && make cp-init
# Workers reconnect automatically

# Worker gone?
make bootstrap-node NODE=<name>
# Or on new machine: make bootstrap
```
