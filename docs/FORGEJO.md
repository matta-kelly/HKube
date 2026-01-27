# Forgejo Git Server

## Overview

Forgejo is the self-hosted Git server running on the anchor VPS. It serves as the source of truth for GitOps deployments via Flux.

- **URL**: https://forgejo.datamountainsolutions.com
- **SSH**: `ssh://git@forgejo.datamountainsolutions.com:2222`
- **Location**: Anchor VPS (behind Caddy reverse proxy)

---

## Repository Setup

### Creating a New Repository

1. Login to https://forgejo.datamountainsolutions.com
2. Click **+** → **New Repository**
3. Fill in:
   - **Repository Name**: e.g., `my-app`
   - **Visibility**: Private (recommended)
   - **Initialize**: No README (if pushing existing code)
4. Click **Create Repository**

### Clone URLs

```bash
# SSH (recommended for CI/CD)
ssh://git@forgejo.datamountainsolutions.com:2222/mkultra/<repo>.git

# HTTPS
https://forgejo.datamountainsolutions.com/mkultra/<repo>.git
```

### Adding Forgejo Remote to Existing Repo

```bash
cd /path/to/repo
git remote add forgejo ssh://git@forgejo.datamountainsolutions.com:2222/mkultra/<repo>.git
git push forgejo main
```

---

## Flux GitOps Integration

### How It Works

Flux watches GitRepositories on Forgejo and automatically applies changes to the cluster. Each app repo needs:

1. A `GitRepository` resource pointing to Forgejo
2. A `Kustomization` resource defining what to deploy
3. A **deploy key** on Forgejo for SSH authentication

### Deploy Keys

Flux uses the `flux-system` secret for SSH authentication. Each repo on Forgejo needs this public key added as a deploy key.

**Get the flux-system public key:**

```bash
KUBECONFIG=generated/kubeconfig.yaml kubectl get secret flux-system -n flux-system \
  -o jsonpath='{.data.identity\.pub}' | base64 -d
```

**Add to Forgejo:**

1. Go to repo → **Settings** → **Deploy Keys**
2. Click **Add Deploy Key**
3. Title: `flux-system`
4. Content: (paste the public key)
5. Leave "Enable write access" unchecked (read-only is sufficient)
6. Click **Add Deploy Key**

### Adding a New App to Flux

1. **Create the repo on Forgejo** (see above)

2. **Push your code to Forgejo**

3. **Add deploy key** (see above)

4. **Create GitRepository in h-kube:**

```yaml
# cluster/namespaces/<app>/source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: <app>
  namespace: flux-system
spec:
  interval: 5m
  url: ssh://git@forgejo.datamountainsolutions.com:2222/mkultra/<app>
  ref:
    branch: main
  secretRef:
    name: flux-system
```

5. **Create Kustomization:**

```yaml
# cluster/namespaces/<app>/<app>.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <app>
  namespace: flux-system
spec:
  interval: 10m
  path: ./
  prune: true
  sourceRef:
    kind: GitRepository
    name: <app>
  targetNamespace: <app>
```

6. **Commit and push h-kube to trigger Flux**

### Current Repositories

| Repo | URL | Purpose |
|------|-----|---------|
| HKube | `ssh://...2222/mkultra/HKube` | Main cluster GitOps |
| homenetes | `ssh://...2222/mkultra/homenetes` | Homelab apps (vaultwarden, immich) |
| homedia | `ssh://...2222/mkultra/homedia` | Media stack (jellyfin, *arr) |

---

## SSH Access

### From Workstation

Your workstation SSH key should be added to your Forgejo account:

1. Go to **Settings** → **SSH / GPG Keys**
2. Add your public key (`~/.ssh/id_ed25519.pub` or similar)

### Testing SSH Access

```bash
ssh -T git@forgejo.datamountainsolutions.com -p 2222
# Should output: Hi there, mkultra! You've successfully authenticated...
```

### SSH Config (Optional)

Add to `~/.ssh/config` for convenience:

```
Host forgejo
    HostName forgejo.datamountainsolutions.com
    User git
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
```

Then use: `git clone forgejo:mkultra/<repo>.git`

---

## Troubleshooting

### Flux Can't Fetch Repository

**Symptom:** GitRepository shows `READY: False` with SSH errors

**Cause:** Missing deploy key

**Fix:** Add the flux-system public key as a deploy key (see above)

### "invalid pkt-len found" Error

**Cause:** SSH authentication failed (usually missing deploy key)

**Fix:**
1. Add deploy key to repo
2. Restart source-controller:
   ```bash
   KUBECONFIG=generated/kubeconfig.yaml kubectl rollout restart deployment source-controller -n flux-system
   ```

### Force Flux Reconciliation

```bash
KUBECONFIG=generated/kubeconfig.yaml kubectl annotate gitrepository <name> -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

### Check GitRepository Status

```bash
KUBECONFIG=generated/kubeconfig.yaml kubectl get gitrepository -n flux-system -o wide
```

---

## API Access

### Generating an API Token

1. Go to **Settings** → **Applications**
2. Under **Manage Access Tokens**, enter a name
3. Select scopes (e.g., `repo` for repository access)
4. Click **Generate Token**
5. Save the token securely (it won't be shown again)

### API Usage Example

```bash
# List repositories
curl -H "Authorization: token <your-token>" \
  https://forgejo.datamountainsolutions.com/api/v1/user/repos

# Create repository
curl -X POST -H "Authorization: token <your-token>" \
  -H "Content-Type: application/json" \
  -d '{"name":"new-repo","private":true}' \
  https://forgejo.datamountainsolutions.com/api/v1/user/repos
```

---

## Infrastructure Details

### Deployment

- Runs as Docker container on anchor VPS
- Config: `/opt/forgejo/docker-compose.yml`
- Data: `/opt/forgejo/data`
- Managed by Ansible role: `ansible/roles/forgejo`

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 443 | HTTPS | Web UI (via Caddy) |
| 2222 | SSH | Git SSH operations |

### Backups

Forgejo data is stored in `/opt/forgejo/data` on anchor. Include this in your backup strategy.
