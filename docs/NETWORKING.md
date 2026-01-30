# Network Architecture

## Overview

H-Kube uses a split-network architecture where all cluster services are behind Tailscale VPN, with only the VPN coordinator (anchor) publicly accessible.

```
┌─────────────────────────────────────────────────────────────┐
│                      Public Internet                         │
│                             │                                │
│              ┌──────────────┼──────────────┐                │
│              │              │              │                │
│              ▼              ▼              ▼                │
│         ┌────────┐    ┌─────────┐    ┌─────────┐           │
│         │ Blocked│    │ anchor  │    │Cloudflare│           │
│         │        │    │ :80/443 │    │ Tunnel   │           │
│         └────────┘    │ :2222   │    │(Jellyfin)│           │
│              │        │ :3478   │    └────┬────┘           │
│              │        └────┬────┘         │                │
└──────────────┼─────────────┼──────────────┼─────────────────┘
               │             │              │
┌──────────────┼─────────────┼──────────────┼─────────────────┐
│              │      Tailscale Network     │                 │
│              │             │              │                 │
│              ▼             ▼              ▼                 │
│         ┌─────────┐   ┌─────────┐   ┌─────────┐            │
│         │cloud-cp │   │  anchor │   │  home   │            │
│         │100.64.0.2   │100.64.0.1   │ nodes   │            │
│         │ Traefik │◄──│  DNS    │   │         │            │
│         │ K8s API │   │Headscale│   │         │            │
│         └─────────┘   └─────────┘   └─────────┘            │
│              ▲                                              │
│              │ DNS queries (split DNS)                      │
│         ┌────┴────┐                                        │
│         │ Clients │ (laptop, phone on Tailscale)           │
│         └─────────┘                                        │
└─────────────────────────────────────────────────────────────┘
```

## Node Configuration

### cloud-cp-1 (K8s Control Plane)

**IPs:**
- Public: `178.156.198.140` (blocked by firewall)
- Tailscale: `100.64.0.2`

**Firewall Rules (UFW):**

| Port | Interface | Purpose |
|------|-----------|---------|
| 22/tcp | tailscale0 | SSH |
| 80/tcp | tailscale0 | HTTP (Traefik) |
| 443/tcp | tailscale0 | HTTPS (Traefik) |
| 6443/tcp | tailscale0 | Kubernetes API |
| 8472/udp | tailscale0 | Flannel VXLAN |

**Access:** Tailscale only. No public ports.

---

### anchor (VPN Coordinator)

**IPs:**
- Public: `5.78.92.191`
- Tailscale: `100.64.0.1`

**Firewall Rules (UFW):**

| Port | Interface | Purpose |
|------|-----------|---------|
| 22/tcp | public (rate limited) | SSH administration |
| 80/tcp | public | Caddy (HTTP→HTTPS redirect) |
| 443/tcp | public | Headscale UI, Forgejo web |
| 2222/tcp | public | Forgejo SSH (git operations) |
| 3478/udp | public | DERP/STUN (NAT traversal) |
| 53/tcp,udp | tailscale0 | DNS (dnsmasq) |

**Access:** Public for VPN enrollment and git. DNS only on tailnet.

**Services:**
- **Headscale** - Tailscale coordination server (self-hosted)
- **Forgejo** - Git server for GitOps
- **Caddy** - Reverse proxy with automatic TLS
- **dnsmasq** - Split DNS for tailnet clients

---

### Home Nodes (gpa-server, monkeybusiness)

**Location:** Behind home NAT

**Firewall:** Minimal (protected by NAT)

**Access:** Tailscale only for external access

---

## DNS Architecture

### Split DNS

Tailscale clients are configured to route specific domains to anchor's DNS server (dnsmasq).

**Split DNS Routes:**
- `*.homenetes.datamountainsolutions.com` → `100.64.0.1`
- `*.kube.datamountainsolutions.com` → `100.64.0.1`

**dnsmasq Configuration** (`/etc/dnsmasq.d/tailscale.conf` on anchor):
```
interface=tailscale0
bind-interfaces
server=1.1.1.1
server=9.9.9.9
address=/homenetes.datamountainsolutions.com/100.64.0.2
address=/kube.datamountainsolutions.com/100.64.0.2
```

### DNS Resolution Flow

```
1. Client requests: jellyfin.homenetes.datamountainsolutions.com
2. Tailscale intercepts (matches split DNS route)
3. Query sent to 100.64.0.1:53 (anchor dnsmasq)
4. dnsmasq returns: 100.64.0.2 (cloud-cp tailscale IP)
5. Client connects to 100.64.0.2:443 via Tailscale
6. Traefik routes to Jellyfin service
```

### Headscale DNS Configuration

Located in `/etc/headscale/config.yaml`:

```yaml
dns:
  magic_dns: true
  base_domain: mesh.datamountainsolutions.com
  nameservers:
    split:
      homenetes.datamountainsolutions.com:
        - 100.64.0.1
      kube.datamountainsolutions.com:
        - 100.64.0.1
    global:
      - 1.1.1.1
      - 9.9.9.9
```

---

## Access Patterns

### From Public Internet

| Destination | Result |
|-------------|--------|
| cloud-cp (any port) | **Blocked** |
| anchor (80/443) | Headscale UI, Forgejo |
| anchor (2222) | Forgejo git SSH |
| anchor (3478) | DERP relay |
| Jellyfin (via Cloudflare Tunnel) | **Works** (when configured) |

### From Tailscale Network

| Destination | Result |
|-------------|--------|
| *.homenetes.datamountainsolutions.com | **Works** via split DNS |
| *.kube.datamountainsolutions.com | **Works** via split DNS |
| Direct IP (100.64.0.x) | **Works** |
| SSH to any node | **Works** |

### From Home Network (no Tailscale)

| Destination | Result |
|-------------|--------|
| Home nodes directly | **Works** (same LAN) |
| cloud-cp services | **Blocked** |
| Jellyfin (via Cloudflare Tunnel) | **Works** (when configured) |

---

## SSH Configuration

SSH config should use Tailscale IPs for cluster nodes:

```
# ~/.ssh/config

Host cloud-cp
  HostName 100.64.0.2
  User mkultra
  IdentityFile ~/.ssh/id_ed25519_hetzner

Host anchor-vps
  HostName 5.78.92.191  # Public IP (anchor stays public)
  User mkultra
  IdentityFile ~/.ssh/id_ed25519_hetzner

Host gpa-server
  HostName 100.64.0.3
  User mkultra
  IdentityFile ~/.ssh/gpa-server

Host monkeybusiness
  HostName 100.64.0.4
  User mkultra
  IdentityFile ~/.ssh/id_ed25519
```

---

## Cloudflare Tunnel (TODO)

For public Jellyfin access without Tailscale:

1. Cloudflare Tunnel runs as pod in cluster
2. Makes outbound connection to Cloudflare edge
3. Routes `jellyfin.homenetes.datamountainsolutions.com` to internal service
4. DNS CNAME points to tunnel instead of public IP

**Status:** Not yet configured

---

## Troubleshooting

### Can't reach services from Tailscale client

1. Check tailscale status: `tailscale status`
2. Check DNS resolution: `dig jellyfin.homenetes.datamountainsolutions.com`
   - Should return `100.64.0.2`
   - If returns public IP, split DNS not working
3. Check tailscale DNS: `tailscale dns status`
   - Should show split DNS routes
4. Restart tailscale: `sudo systemctl restart tailscaled`

### Headscale not responding (502)

1. Check headscale on anchor: `ssh anchor-vps 'sudo systemctl status headscale'`
2. Check logs: `ssh anchor-vps 'sudo journalctl -u headscale -n 50'`
3. Common issue: YAML config corruption - validate with `python -c "import yaml; yaml.safe_load(open('/etc/headscale/config.yaml'))"`

### DNS not resolving via split DNS

1. Check dnsmasq on anchor: `ssh anchor-vps 'sudo systemctl status dnsmasq'`
2. Test from anchor: `ssh anchor-vps 'dig @100.64.0.1 jellyfin.homenetes.datamountainsolutions.com'`
3. Check UFW allows port 53: `ssh anchor-vps 'sudo ufw status | grep 53'`

---

## Files Reference

| File | Location | Purpose |
|------|----------|---------|
| Headscale config | anchor:/etc/headscale/config.yaml | VPN coordinator config |
| Headscale ACL | anchor:/etc/headscale/acl.yaml | Access control rules |
| dnsmasq config | anchor:/etc/dnsmasq.d/tailscale.conf | Split DNS records |
| UFW rules | Each node | Firewall rules |

### IaC Templates

| Template | Purpose |
|----------|---------|
| `ansible/roles/headscale/templates/config.yaml.j2` | Headscale config |
| `ansible/roles/headscale/templates/acl.yaml.j2` | Headscale ACL |
| `ansible/roles/base/tasks/main.yaml` | UFW firewall setup |

**Note:** dnsmasq is not yet in IaC - manually configured on anchor.

---

## Security Model

1. **Defense in depth:** Multiple layers (firewall + VPN + app auth)
2. **Zero trust on public network:** cloud-cp has no public ports
3. **Anchor as single entry point:** Only VPN coordinator is public
4. **Split DNS:** Internal domains only resolve on tailnet
5. **App-level auth:** Authentik SSO for web services, Jellyfin built-in auth
