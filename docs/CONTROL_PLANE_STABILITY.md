# Control Plane Stability - Incident Log

## 2026-01-29: gpa-server Crash & Disk Bloat Investigation

### Root Causes Identified

1. **gpa-server crash**: SeaweedFS CSI mount (`weed mount`) memory leak
   - Was running `:dev` image with known memory leak
   - Used 5GB RAM before crash, causing node to zombie
   - `cacheCapacityMB=0` helps but doesn't fully fix (known upstream issue)

2. **Disk bloat (monkeybusiness 68%, gpa-server 57%)**:
   - 90 dangling container images (~32GB) - CLEANED
   - CNPG databases: WAL accumulation from failed S3 archiving
   - SeaweedFS: ~230GB per node (expected for media storage)

### Fixes Deployed

1. **SeaweedFS CSI** (`cluster/infrastructure/services/seaweedfs/csi-release.yaml`):
   - Pinned to `v1.4.2` (was `:dev`/`:latest`)
   - Set `cacheCapacityMB: 0` to disable file caching
   - **STATUS**: Complete - pods restarted, v1.4.2 running on all nodes
   - Note: CSI uses `OnDelete` update strategy, requires manual pod deletion after image changes

2. **Monitoring stack** (`cluster/infrastructure/services/kube-prometheus-stack/release.yaml`):
   - Moved Prometheus, Grafana, Alertmanager to monkeybusiness
   - nodeSelector changed to `kubernetes.io/hostname: monkeybusiness`
   - **STATUS**: Complete, pods running on monkeybusiness

3. **CNPG database backups** - Disabled failing archives to stop WAL bloat:
   - **STATUS**: All failing backups disabled, WAL will auto-recycle

### CNPG Backup Status (as of 2026-01-29)

| Namespace | Cluster | Backup Status | WAL Size | Notes |
|-----------|---------|---------------|----------|-------|
| airbyte | airbyte-db | DISABLED | 577M | Was 95GB, recovered |
| authentik | authentik-db | DISABLED | 150G | Waiting for checkpoint |
| default | immich-db | DISABLED | 84G | Orphaned, kubectl patched |
| default | vaultwarden-db | DISABLED | 321M | Orphaned, kubectl patched |
| homenetes | immich-db | DISABLED | 23G | kubectl patched, update homenetes repo |
| homenetes | vaultwarden-db | DISABLED | 8.2G | kubectl patched, update homenetes repo |
| lotus-lake | dagster-db | **Working** | 577M | Different creds, actually working |
| lotus-lake | ducklake-db | **Working** | 577M | Different creds, actually working |

**Root cause**: S3 credentials for `cnpg-backups` bucket are broken. lotus-lake databases use different credentials that work.

### Still TODO

1. **Update homenetes repo** to persist backup disable:
   - kubectl patches will revert on Flux reconcile
   - Clone `ssh://git@forgejo.datamountainsolutions.com:2222/mkultra/homenetes`
   - Comment out backup sections in immich-db and vaultwarden-db

2. **Clean dangling images on gpa-server** (only did monkeybusiness):
   ```bash
   ssh gpa-server "sudo crictl rmi --prune"
   ```

3. **Investigate default namespace databases**:
   - default/immich-db and default/vaultwarden-db are orphaned (no Flux labels)
   - Duplicates of homenetes/* - can likely be deleted

4. **Fix S3 credentials for cnpg-backups**:
   - Compare working lotus-lake creds vs broken ones
   - Re-enable backups once fixed

5. **Monitor WAL sizes**:
   - After checkpoint, bloated WALs should shrink
   - Verify authentik (150G) and default/immich (84G) recover

6. **Investigate remaining disk usage** on monkeybusiness:
   - ~220GB still unaccounted after SeaweedFS + images + PVCs
   - Likely containerd layers/snapshots

### Key Files Modified

- `cluster/infrastructure/services/seaweedfs/csi-release.yaml` - CSI version + cache
- `cluster/infrastructure/services/kube-prometheus-stack/release.yaml` - monitoring nodeSelector
- `cluster/infrastructure/services/airbyte/database.yaml` - backup disabled

### Reference: SeaweedFS Memory Leak

Known issue in `weed mount`: https://github.com/seaweedfs/seaweedfs/issues/7270

Memory grows during file operations, especially large downloads. `cacheCapacityMB=0` reduces but doesn't eliminate. Stable images (v1.4.x) may have fixes not in `:dev`.
