# H-Kube Project Guidelines

## Cluster Access

**SSH Hosts** (use these names, defined in ~/.ssh/config):
- `cloud-cp` - Control plane node (Hetzner)
- `gpa-server` - Worker node (local)

**Kubectl**: Always use `sudo kubectl` when running commands on cluster nodes.

```bash
# Correct
ssh cloud-cp "sudo kubectl get pods -A"

# Wrong - permission denied
ssh cloud-cp "kubectl get pods -A"
```

## Secrets Management

**Always use SOPS** for any secrets in the cluster directory:

```bash
# Encrypt a new secret
sops -e -i cluster/path/to/secret.yaml

# Edit an encrypted secret
sops cluster/path/to/secret.yaml

# View decrypted content
sops -d cluster/path/to/secret.yaml
```

**Never commit plaintext secrets** to git. All secrets must be SOPS-encrypted before committing.

The age key is stored in `~/.config/sops/age/keys.txt` locally and in the `sops-age` secret in the `flux-system` namespace.

## Flux Variables

**Never hardcode domains or emails**. Use Flux variable substitution:

Variables are defined in `cluster/cluster-vars.yaml`:
- `${DOMAIN}` - Base domain (datamountainsolutions.com)
- `${CLUSTER_DOMAIN}` - Cluster subdomain (kube.datamountainsolutions.com)
- `${ADMIN_EMAIL}` - Admin email for certs, etc.

```yaml
# Correct
hosts:
  - grafana.${CLUSTER_DOMAIN}

# Wrong - hardcoded
hosts:
  - grafana.kube.datamountainsolutions.com
```

## Node Labels & Placement

**Never hardcode hostnames** in nodeSelector. Use labels instead:

### Standard Labels (applied during bootstrap)

| Label | Values | Meaning |
|-------|--------|---------|
| `node.h-kube.io/role` | `server`, `agent` | Control plane vs worker |
| `storage.h-kube.io/nvme` | `true` | Node has NVMe storage |
| `storage.h-kube.io/bulk` | `true` | Node has bulk HDD storage |

### Usage in Manifests

```yaml
# Correct - uses labels (works on any node with bulk storage)
nodeSelector:
  storage.h-kube.io/bulk: "true"

# Wrong - hardcoded hostname
nodeSelector:
  kubernetes.io/hostname: gpa-server
```

### Placement Guidelines

**Control plane (`node.h-kube.io/role: server`):**
- Flux controllers
- CoreDNS
- Lightweight metadata services (SeaweedFS master/filer)

**Workers with bulk storage (`storage.h-kube.io/bulk: "true"`):**
- SeaweedFS volumes
- Application data

**Workers with NVMe (`storage.h-kube.io/nvme: "true"`):**
- Databases
- Caches
- Performance-sensitive workloads

### View Cluster State

```bash
# Generate cluster-config.yaml from live cluster
make cluster-status

# View node labels directly
ssh cloud-cp "sudo kubectl get nodes --show-labels"
```

## GitOps Workflow

1. Make changes to YAML files in `cluster/`
2. Encrypt any secrets with SOPS
3. Commit and push to main branch
4. Flux automatically reconciles (or force with annotation)

**Force reconcile**:
```bash
ssh cloud-cp "sudo kubectl annotate --overwrite -n flux-system kustomization/flux-system reconcile.fluxcd.io/requestedAt=\"\$(date +%s)\""
```

## Storage

**local-path-provisioner** is configured per node in `cluster/infrastructure/configs/local-path/`:
- `gpa-server`: `/mnt/bulk-storage/k3s` (1TB HDD)
- Default: `/var/lib/rancher/k3s/storage` (NVMe/SSD)

**SeaweedFS** provides distributed storage:
- S3-compatible API for object storage
- CSI driver for PVCs (future)

## Directory Structure

```
cluster/
├── cluster-vars.yaml          # Flux variables (domain, email, etc.)
├── kustomization.yaml         # Root kustomization
├── flux-system/               # Flux bootstrap (don't modify gotk-components.yaml)
└── infrastructure/
    ├── controllers/           # Operators (cert-manager, traefik, cnpg)
    ├── configs/               # CRD-dependent configs (ClusterIssuers, middlewares, local-path)
    └── services/              # Applications (authentik, prometheus, seaweedfs)
```

## Authentication

**Authentik** is the SSO provider at `auth.${CLUSTER_DOMAIN}`:
- Grafana uses OAuth2 (native integration)
- Other services use Traefik ForwardAuth middleware

**Traefik ForwardAuth**: Add this annotation to protect any ingress:
```yaml
annotations:
  traefik.ingress.kubernetes.io/router.middlewares: kube-system-authentik-auth@kubernetescrd
```

## Research Before Acting

When encountering issues:
1. Check official documentation first
2. Verify versions and compatibility
3. Don't trial-and-error - understand the problem before fixing
