# Security Architecture

## Two-Layer Security Model

H-Kube uses two distinct security layers for different access patterns:

### Layer 1: Web Application SSO (Public + Authenticated)
**Technology:** Authentik Forward Auth + Traefik
**Use Case:** Web-based services accessible from internet

**How it works:**
1. Service exposed at `*.landl.datamountainsolutions.com` (public DNS)
2. Traefik middleware intercepts requests
3. Authentik checks authentication via browser session
4. If not logged in → redirect to Authentik login page
5. If logged in → access granted

**Protected Services:**
- Airbyte (`airbyte.landl.datamountainsolutions.com`)
- Any other web UIs added to the cluster

**Configuration:**
- **Middleware:** `cluster/infrastructure/configs/traefik-auth/middleware-lotus-lake.yaml`
- **Ingresses:** Each service adds annotation: `traefik.ingress.kubernetes.io/router.middlewares: kube-system-authentik-lotus-lake@kubernetescrd`
- **Authentik Provider:** `landl-proxy` (Forward Auth, domain-level)
- **Authentik Application:** "Lotus & Luna"
- **Access Control:** Users in `landl-users` group

### Layer 2: Network-Level VPN (Private + ACL-Restricted)
**Technology:** Headscale (self-hosted Tailscale) + OIDC
**Use Case:** Direct database/service access, SSH, internal ports

**How it works:**
1. User installs Tailscale client
2. Connects via `--login-server=https://headscale.datamountainsolutions.com`
3. Authenticates through Authentik OIDC
4. Joins tailnet, gets assigned IP (e.g., `100.64.0.6`)
5. Headscale ACLs restrict what they can access based on group

**Protected Services:**
- DuckLake Postgres (`100.64.0.6:5432`)
- SSH access to nodes
- Internal cluster services
- Any port-specific access

**Configuration:**
- **Headscale Config:** `ansible/roles/headscale/templates/config.yaml.j2`
- **ACL Rules:** `ansible/roles/headscale/templates/acl.yaml.j2`
- **Deployed to:** `/etc/headscale/` on anchor VPS
- **Authentik Provider:** "Headscale" (OAuth2/OIDC)
- **Access Control:** Email-based groups in ACL file

---

## User Access Matrix

| User Type | Web Apps (Port 80/443) | Direct DB Access (Port 5432) | SSH | Full Admin |
|-----------|----------------------|----------------------------|-----|-----------|
| **admin** (mkultra) | ✅ Via SSO | ✅ Via VPN | ✅ Via VPN | ✅ |
| **landl-users** (boss, employees) | ✅ Via SSO | ✅ Via VPN | ❌ | ❌ |
| **tag:infra** (nodes) | N/A | ✅ Node-to-node | ✅ | ❌ |

---

## Key Security Principles

### 1. **Defense in Depth**
- Web apps: Public but SSO-protected
- Databases: VPN + ACL-restricted
- SSH: VPN + ACL-restricted to admins only

### 2. **Least Privilege**
- `landl-users` get ONLY what they need (ports 80/443/5432)
- Infra nodes can only talk to each other
- Admin access is limited to specific emails

### 3. **Single Sign-On**
- One Authentik account for all services
- Same credentials for web apps and VPN
- Centralized user management

### 4. **Zero Trust Network**
- Default deny in Headscale ACLs
- Explicit allow rules for each access pattern
- No wide-open `*:*` rules (except for admin)

---

## Authentication Flow

### Web App Access
```
User → https://airbyte.landl.datamountainsolutions.com
  → Traefik middleware checks auth
  → Authentik embedded outpost validates session
  → If no session: redirect to auth.landl.datamountainsolutions.com
  → User logs in with Authentik credentials
  → Redirected back to app
  → Access granted
```

### VPN Access
```
User → tailscale up --login-server=https://headscale.datamountainsolutions.com
  → Browser opens to Headscale OIDC endpoint
  → Redirects to Authentik
  → User logs in with Authentik credentials
  → Authentik returns OIDC token with user info
  → Headscale validates token
  → User added to tailnet with email-based ACL rules
  → Access granted per ACL group membership
```

---

## Allowed Domains

Headscale OIDC allows login from these email domains:
- `@datamountainsolutions.com` (internal infrastructure)
- `@lotusandluna.com` (Landl employees)

**File:** `/etc/headscale/config.yaml` on anchor VPS
**Template:** `ansible/roles/headscale/templates/config.yaml.j2`

---

## Security Checklist

- [ ] All web services use Authentik middleware (no public unauthed access)
- [ ] Headscale ACLs follow least privilege (no unnecessary `*:*` rules)
- [ ] Only `landl-users` and `admin` groups in Authentik have access
- [ ] SSH is restricted to admin group only
- [ ] Database ports (5432) only accessible via VPN
- [ ] All users use External type in Authentik (prevent admin escalation)
- [ ] Regular review of ACL rules and group memberships
