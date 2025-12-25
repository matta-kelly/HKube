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

## Node Placement

**Control plane (cloud-cp)**: Only critical control plane components
- Flux controllers
- CoreDNS
- CNPG databases (for now)

**Worker node (gpa-server)**: All application workloads
- Authentik
- Grafana
- Prometheus
- Alertmanager
- User applications

Use `nodeSelector` to place workloads:
```yaml
nodeSelector:
  kubernetes.io/hostname: gpa-server
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

## Directory Structure

```
cluster/
├── cluster-vars.yaml          # Flux variables (domain, email, etc.)
├── kustomization.yaml         # Root kustomization
├── flux-system/               # Flux bootstrap (don't modify gotk-components.yaml)
└── infrastructure/
    ├── controllers/           # Operators (cert-manager, traefik, cnpg)
    ├── configs/               # CRD-dependent configs (ClusterIssuers, middlewares)
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
