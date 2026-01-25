# H-Kube Architecture

## System Overview

H-Kube is a hybrid Kubernetes cluster spanning cloud and home infrastructure, secured by Headscale VPN and Authentik SSO.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Public Internet                          │
└────────────┬────────────────────────────────────┬───────────────┘
             │                                    │
             │ HTTPS (443)                        │ Tailscale/DERP
             │                                    │
      ┌──────▼──────┐                      ┌──────▼──────┐
      │   Traefik   │                      │  Headscale  │
      │   Ingress   │◄─────────────────────┤   (anchor)  │
      │             │   VPN Mesh (WireGuard)│             │
      └──────┬──────┘                      └─────────────┘
             │                                    │
             │ Forward Auth                       │ OIDC Auth
             │                                    │
      ┌──────▼──────┐                      ┌──────▼──────┐
      │  Authentik  │◄─────────────────────┤             │
      │    SSO      │    OIDC Provider     │             │
      └─────────────┘                      └─────────────┘
             │
             │ Validates Auth
             │
      ┌──────▼───────────────────────────────────────────┐
      │         Kubernetes Cluster (K3s)                 │
      │  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
      │  │ Airbyte  │  │ DuckLake │  │  Other   │      │
      │  │          │  │ Postgres │  │ Services │      │
      │  └──────────┘  └──────────┘  └──────────┘      │
      └──────────────────────────────────────────────────┘
```

---

## Infrastructure Nodes

### Cloud Nodes (Hetzner)

**anchor (VPS)**
- **Role:** Bootstrap layer (VPN + Git)
- **IP:** Oregon datacenter (public), `100.64.0.1` (tailnet)
- **Services:**
  - Caddy (reverse proxy, TLS termination)
  - Headscale (VPN coordinator)
  - Forgejo (Git server)
  - HAProxy (k3s API load balancer)
- **Not part of K3s cluster**

**cloud-cp-1 (VPS)**
- **Role:** K3s control plane
- **IP:** `178.156.198.140` (public), `100.64.0.2` (tailnet)
- **Services:** K3s server, etcd

### Home Nodes

**gpa-server**
- **Role:** K3s control plane (home)
- **IP:** `192.168.50.10` (LAN), `100.64.0.3` (tailnet)
- **Hostname:** `k3s-control-1` on tailnet
- **Storage:** NVMe (fast), HDD (bulk)

**monkeybusiness**
- **Role:** K3s worker (home)
- **IP:** `192.168.50.90` (LAN), `100.64.0.4` (tailnet)
- **Services:** DuckLake Postgres, other workloads
- **Storage:** 1TB HDD (bulk)

---

## Networking Architecture

### Tailscale Mesh (via Headscale)
- **Network:** `100.64.0.0/10`
- **Coordinator:** anchor VPS (`headscale.datamountainsolutions.com`)
- **DERP Server:** Embedded in Headscale (port 3478/UDP, 443/TCP)
- **Nodes:** All infrastructure + user devices

**Key Features:**
- WireGuard encrypted peer-to-peer
- NAT traversal (cloud ↔ home connectivity)
- ACL-based access control
- OIDC authentication via Authentik

### DNS Domains

| Domain | Purpose | Exposed To |
|--------|---------|-----------|
| `*.kube.datamountainsolutions.com` | Internal cluster services | Internet (SSO-protected) |
| `*.landl.datamountainsolutions.com` | Landl client services | Internet (SSO-protected) |
| `headscale.datamountainsolutions.com` | VPN coordinator | Internet (public) |
| `mesh.datamountainsolutions.com` | Headscale UI | Internet (admin only) |

### Ingress Flow

```
User Request
  → Public DNS (Cloudflare/etc)
  → anchor VPS (5.78.92.191:443)
  → Traefik Ingress Controller (in cluster)
  → Authentik Middleware (forward auth check)
  → Backend Service (if authorized)
```

---

## Authentication & Authorization

### Authentik Setup

**Components:**
- **PostgreSQL:** CloudNativePG cluster for auth data
- **Server:** Helm-deployed in `authentik` namespace
- **Embedded Outpost:** ForwardAuth provider for Traefik

**Providers:**

1. **kube-domain** (Proxy Provider)
   - Domain: `*.kube.datamountainsolutions.com`
   - Users: Internal infrastructure (admin group)

2. **landl-proxy** (Proxy Provider)
   - Domain: `*.landl.datamountainsolutions.com`
   - Users: Landl employees (landl-users group)

3. **Headscale** (OAuth2/OIDC Provider)
   - Endpoint: `/application/o/headscale/`
   - Scopes: openid, profile, email, groups
   - Users: Both admin and landl-users

**Groups:**
- `admin` → Full cluster access
- `landl-users` → Limited to Landl services
- `authentik Admins` → Authentik management

### Headscale ACLs

**File:** `/etc/headscale/acl.yaml` on anchor VPS
**Template:** `ansible/roles/headscale/templates/acl.yaml.j2`
**Config:** `config/config.yaml` (acl section)

```json
{
  "groups": {
    "group:admin": ["mattakellyy@gmail.com"],
    "group:landl-users": ["matthew.kelly@lotusandluna.com"]
  },
  "acls": [
    {"action": "accept", "src": ["group:admin"], "dst": ["*:*"]},
    {"action": "accept", "src": ["h-kube"], "dst": ["*:*"]},
    {"action": "accept", "src": ["group:landl-users"], "dst": ["*:80", "*:443", "*:5432"]}
  ]
}
```

**Access Levels:**
- `group:admin` - Full access (personal admin account)
- `h-kube` - Full access (infrastructure service account, used by all nodes)
- `group:landl-users` - Limited to web (80/443) + database (5432) only

**Key Points:**
- Email-based group membership
- Default deny (no `*:*` rule except admin and h-kube)
- Port-specific restrictions for landl-users
- ACL emails defined in `config/config.yaml` and templated via Ansible

---

## Service Deployment Architecture

### GitOps with Flux

**Repository:** `github.com/matta-kelly/HKube`
**Structure:**
```
cluster/
├── infrastructure/
│   ├── configs/         # ConfigMaps, Secrets
│   │   └── traefik-auth/
│   │       └── middleware-lotus-lake.yaml
│   ├── services/        # Helm releases
│   │   ├── authentik/
│   │   ├── airbyte/
│   │   └── ...
│   └── namespaces/
└── apps/
    └── lotus-lake/      # Client workloads
        └── ducklake-db.yaml
```

**Deployment Flow:**
1. Push to GitHub main branch
2. Flux detects changes
3. Helm releases updated
4. Kustomizations applied
5. Services reconciled

### Storage Architecture

**Local Storage:**
- **Class:** `local-path` (default)
- **Backed by:** Node filesystem
- **Use case:** Non-critical, ephemeral data

**CloudNativePG:**
- **Databases:** Authentik, DuckLake metadata
- **Backups:** SeaweedFS S3 (internal cluster storage)
- **Retention:** 7 days

**SeaweedFS:**
- **Type:** Distributed object storage (S3-compatible)
- **Use case:** Backups, large files
- **Namespace:** `seaweedfs`

---

## Configuration Management

### Ansible Inventory Generation

**Source Files:**
- `config/config.yaml` → Node definitions, versions, settings
- `config/secrets.env` → API keys, tokens (gitignored)

**Generator:**
```bash
cd ~/bode/h-kube
make generate  # Runs scripts/generate.py
```

**Output:**
- `generated/inventory.yml` → Ansible inventory with all vars

### Deployment Commands

| Command | Purpose |
|---------|---------|
| `make anchor-configure` | Deploy Headscale config to anchor VPS |
| `make cp-configure` | Deploy K3s to control plane |
| `make bootstrap-node NODE=name` | Bootstrap any node |
| `make generate` | Regenerate inventory from config |

### Critical Files

**OIDC Configuration:**
- Template: `ansible/roles/headscale/templates/config.yaml.j2`
- Deployed: `/etc/headscale/config.yaml` on anchor
- Contains: Client ID, secret path, allowed domains

**ACL Configuration:**
- Template: `ansible/roles/headscale/templates/acl.yaml.j2`
- Deployed: `/etc/headscale/acl.yaml` on anchor
- Contains: Group definitions, access rules

**Traefik Auth Middleware:**
- File: `cluster/infrastructure/configs/traefik-auth/middleware-lotus-lake.yaml`
- Applied: Cluster-wide via Flux
- Referenced: By ingress annotations

---

## Data Flow Examples

### Example 1: User Accesses Airbyte Web UI

```
1. User → https://airbyte.landl.datamountainsolutions.com
2. DNS → 5.78.92.191 (anchor VPS)
3. Traefik Ingress → Receives request
4. Middleware → Calls Authentik forward auth endpoint
5. Authentik → Checks browser session
   - No session? → Redirect to auth.landl.datamountainsolutions.com
   - Has session? → Validate user in landl-users group
6. Authentik → Returns auth headers to Traefik
7. Traefik → Proxies to airbyte-server pod
8. User → Sees Airbyte UI
```

### Example 2: User Connects to DuckLake via Power BI

```
1. User → tailscale up --login-server=https://headscale...
2. Headscale → OIDC redirect to Authentik
3. User → Logs in with credentials
4. Authentik → Returns OIDC token
5. Headscale → Validates token, assigns IP 100.64.0.X
6. Headscale → Checks ACL: user in group:landl-users
7. ACL → Allows dst: tag:infra:5432
8. User → WireGuard tunnel established
9. Power BI → Connects to 100.64.0.4:5432
10. PostgreSQL → Connection accepted
```

### Example 3: GitOps Deployment of New Service

```
1. Developer → Pushes new HelmRelease to GitHub
2. Flux → Polls repository every 1m
3. Flux → Detects new commit
4. Kustomization → Reconciles cluster/ directory
5. HelmRelease → Triggers Helm chart installation
6. Helm → Creates Deployment, Service, Ingress
7. Ingress → Traefik picks up new route
8. cert-manager → Provisions TLS certificate
9. Service → Live at https://newservice.landl...
```

---

## Observability

### Logs
- **Headscale:** `ssh anchor-vps "sudo journalctl -u headscale -f"`
- **Cluster:** `kubectl logs -n <namespace> <pod>`

### Status Checks
```bash
# Headscale
ssh anchor-vps "sudo headscale nodes list"

# Kubernetes
kubectl get nodes
kubectl get pods -A

# Flux
flux get kustomizations
flux get helmreleases -A
```

---

## Disaster Recovery

### Backups
- **Authentik DB:** Daily backups to SeaweedFS S3 (7d retention)
- **DuckLake DB:** Daily backups to SeaweedFS S3 (7d retention)
- **Headscale DB:** SQLite at `/var/lib/headscale/db.sqlite` (manual backup)

### Recovery Procedures

**Recreate Headscale:**
1. Restore `/var/lib/headscale/db.sqlite`
2. Run `make anchor-configure`
3. Verify nodes reconnect

**Recreate Kubernetes Cluster:**
1. Bootstrap control plane: `make cp-init`
2. Join workers: `make bootstrap-node NODE=<name>`
3. Flux auto-deploys all services from GitHub
4. Restore DB backups if needed

**Restore Authentik:**
1. CNPG automatically recovers from backups
2. If full reinstall: Restore from S3 backup manually

---

## Security Hardening

- [x] SSH password auth disabled
- [x] SSH root login disabled
- [x] Firewall (UFW) on all nodes
- [x] Default deny network policies (Headscale ACLs)
- [x] TLS certificates via cert-manager (Let's Encrypt)
- [x] Secrets encrypted in Git (SOPS + Age)
- [x] Authentik session timeout: 180 days (configurable)
- [x] Headscale OIDC token expiry: 180 days (configurable)

---

## Future Architecture Considerations

- **Multi-region DERP servers** for improved latency
- **CloudNativePG streaming replication** for HA databases
- **External Secrets Operator** for dynamic secret injection
- **ArgoCD** as alternative to Flux (evaluation needed)
- **Prometheus + Grafana** for metrics and monitoring
- **Loki** for centralized log aggregation
