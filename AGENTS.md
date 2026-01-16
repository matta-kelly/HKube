# H-Kube Project Guidelines

## Configuration Pattern

**Source of Truth:**
- `config/config.yaml` - Node definitions, labels, SSH keys
- `config/secrets.env` - Tokens and secrets

**Generated Files** (in `generated/`):
- `inventory.yml` - Ansible inventory
- `cluster-config.yaml` - Live cluster state
- `network-status.yaml` - Tailscale mesh state

**Workflow:**
```bash
make generate       # config/ -> generated/inventory.yml
make cluster-status # Live cluster -> generated/cluster-config.yaml
```

## Cluster Access

**SSH Hosts** (defined in ~/.ssh/config):
- `cloud-cp` - Control plane (Hetzner)
- `gpa-server` - Home worker

**Kubectl**: Always use `sudo kubectl` on cluster nodes:
```bash
ssh cloud-cp "sudo kubectl get pods -A"
```

## Node Labels

All labels use standardized prefixes:

| Prefix | Purpose |
|--------|---------|
| `node.h-kube.io/*` | Node metadata (role, type, location) |
| `storage.h-kube.io/*` | Storage capabilities (nvme, bulk) |
| `capability.h-kube.io/*` | Hardware features (gpu) |

### Standard Labels

| Label | Values | Meaning |
|-------|--------|---------|
| `node.h-kube.io/role` | `server`, `agent` | K3s role |
| `node.h-kube.io/type` | `cloud`, `home` | Deployment type |
| `node.h-kube.io/location` | `cloud`, `home` | Physical location |
| `storage.h-kube.io/bulk` | `true`, `false` | Has bulk HDD |
| `storage.h-kube.io/nvme` | `true`, `false` | Has fast NVMe |

### Workload Placement

```yaml
# Correct - uses labels
nodeSelector:
  storage.h-kube.io/bulk: "true"

# Wrong - hardcoded hostname
nodeSelector:
  kubernetes.io/hostname: gpa-server
```

**Placement patterns:**
- `storage.h-kube.io/bulk: "true"` - Data-heavy apps (Immich, Prometheus)
- `node.h-kube.io/role: server` - Lightweight metadata (SeaweedFS master)
- `node.h-kube.io/location: home` - Colocated apps needing local access

## Secrets Management

**SOPS** for cluster secrets:
```bash
sops -e -i cluster/path/to/secret.yaml  # Encrypt
sops cluster/path/to/secret.yaml         # Edit
sops -d cluster/path/to/secret.yaml      # View
```

Age key: `~/.config/sops/age/keys.txt`

## Flux Variables

Defined in `cluster/cluster-vars.yaml`:
- `${DOMAIN}` - Base domain
- `${CLUSTER_DOMAIN}` - Cluster subdomain
- `${ADMIN_EMAIL}` - Admin email

```yaml
# Correct
hosts:
  - grafana.${CLUSTER_DOMAIN}

# Wrong - hardcoded
hosts:
  - grafana.kube.datamountainsolutions.com
```

## Bootstrap Process

**Remote bootstrap** (from workstation):
```bash
make bootstrap-node NODE=<name>
```

Runs these roles in order:
1. `base` - Security hardening (optional, for fresh systems)
2. `tailscale` - Join mesh
3. `common` - K8s prerequisites
4. `k3s` - Install k3s with labels from inventory
5. `flux` - GitOps (server only)

**Local bootstrap** (on the node):
```bash
make join-mesh NODE_HOSTNAME=<name>
make bootstrap NODE_HOSTNAME=<name>
```

## Storage

**local-path-provisioner** paths:
- `gpa-server`: `/mnt/bulk-storage/k3s` (bulk HDD)
- Default: `/var/lib/rancher/k3s/storage` (NVMe/SSD)

Config: `cluster/infrastructure/configs/local-path/configmap.yaml`

**SeaweedFS** provides:
- S3-compatible storage
- Backup destination for CNPG databases

## Directory Structure

```
cluster/
├── cluster-vars.yaml          # Flux variables
├── flux-system/               # Flux bootstrap
└── infrastructure/
    ├── controllers/           # Operators (cert-manager, traefik, cnpg)
    ├── configs/               # CRDs (issuers, middlewares, local-path)
    └── services/              # Apps (authentik, prometheus, seaweedfs)

config/
├── config.yaml                # Node definitions (SSOT)
└── secrets.env                # Tokens/secrets

generated/
├── inventory.yml              # Ansible inventory
├── cluster-config.yaml        # Cluster state
└── network-status.yaml        # Mesh state
```

## Common Tasks

**Add a new node:**
1. Add to `config/config.yaml`
2. `make generate`
3. `make bootstrap-node NODE=<name>`
4. `make cluster-status` to verify

**Update node labels:**
1. Edit `config/config.yaml`
2. `make generate`
3. `make node-configure NODE=<name>`

**Force Flux reconcile:**
```bash
ssh cloud-cp "sudo kubectl annotate --overwrite -n flux-system kustomization/flux-system reconcile.fluxcd.io/requestedAt=\"\$(date +%s)\""
```

## Principles

1. **Config drives state** - `config/config.yaml` is the source of truth
2. **Generate, don't edit** - Never edit files in `generated/`
3. **Labels, not hostnames** - Use labels for workload placement
4. **Document as you go** - Problems become documentation
