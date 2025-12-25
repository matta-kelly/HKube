#!/bin/bash
# ==============================================================================
# Generate Cluster Config
# ==============================================================================
# Generates cluster-config.yaml from current cluster state.
# This is DOCUMENTATION, not source of truth - labels on nodes are authoritative.
#
# Usage: ./scripts/generate-cluster-config.sh
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_FILE="$PROJECT_ROOT/cluster-config.yaml"

# Determine how to access the cluster
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null 2>&1; then
    KUBECTL="kubectl"
elif ssh cloud-cp "sudo kubectl cluster-info" &> /dev/null 2>&1; then
    KUBECTL="ssh cloud-cp sudo kubectl"
else
    echo "Error: Cannot access cluster. Ensure kubectl is configured or cloud-cp is reachable."
    exit 1
fi

echo "Generating cluster configuration..."

# Get node information
NODES_JSON=$($KUBECTL get nodes -o json)

# Start building the YAML
cat > "$OUTPUT_FILE" << 'HEADER'
# ==============================================================================
# Cluster Configuration (Auto-Generated)
# ==============================================================================
# This file is generated from the live cluster state.
# Run: ./scripts/generate-cluster-config.sh
#
# NOTE: This is documentation, not source of truth.
#       Node labels in Kubernetes are authoritative.
# ==============================================================================

HEADER

echo "nodes:" >> "$OUTPUT_FILE"

# Parse each node
echo "$NODES_JSON" | jq -r '.items[] | @base64' | while read -r node; do
    _jq() {
        echo "$node" | base64 --decode | jq -r "$1"
    }

    name=$(_jq '.metadata.name')
    role=$(_jq '.metadata.labels["node.h-kube.io/role"] // "unknown"')
    has_nvme=$(_jq '.metadata.labels["storage.h-kube.io/nvme"] // "false"')
    has_bulk=$(_jq '.metadata.labels["storage.h-kube.io/bulk"] // "false"')
    tailscale_ip=$(_jq '.status.addresses[] | select(.type=="InternalIP") | .address')
    k8s_version=$(_jq '.status.nodeInfo.kubeletVersion')
    os=$(_jq '.status.nodeInfo.osImage')
    arch=$(_jq '.status.nodeInfo.architecture')

    # Get capacity
    cpu=$(_jq '.status.capacity.cpu')
    memory=$(_jq '.status.capacity.memory')

    cat >> "$OUTPUT_FILE" << EOF
  $name:
    role: $role
    tailscale_ip: $tailscale_ip
    kubernetes_version: $k8s_version
    os: $os
    arch: $arch
    resources:
      cpu: $cpu
      memory: $memory
    storage:
      nvme: $has_nvme
      bulk: $has_bulk

EOF
done

echo ""
echo "Generated: $OUTPUT_FILE"
echo ""
cat "$OUTPUT_FILE"
