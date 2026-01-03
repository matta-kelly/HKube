#!/bin/bash
# ==============================================================================
# Document Cluster State
# ==============================================================================
# Queries the live K3s cluster and generates cluster-config.yaml.
# This is DOCUMENTATION, not source of truth.
#
# Usage: make cluster-status
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_ROOT/generated"
OUTPUT_FILE="$OUTPUT_DIR/cluster-config.yaml"

mkdir -p "$OUTPUT_DIR"

# Determine how to access the cluster
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null 2>&1; then
    KUBECTL="kubectl"
elif ssh cloud-cp "sudo kubectl cluster-info" &> /dev/null 2>&1; then
    KUBECTL="ssh cloud-cp sudo kubectl"
else
    echo "Error: Cannot access cluster. Ensure kubectl is configured or cloud-cp is reachable."
    exit 1
fi

echo "Documenting cluster state..."

# Start building the YAML
cat > "$OUTPUT_FILE" << 'HEADER'
# ==============================================================================
# Cluster State (GENERATED - DO NOT EDIT)
# ==============================================================================
# Generated from: live K3s cluster
# Regenerate with: make cluster-status
#
# This documents what's running. Config source of truth is in:
#   - config/config.yaml (node config)
#   - cluster/ (app manifests)
# ==============================================================================

HEADER

# ==============================================================================
# NODES
# ==============================================================================
echo "  Collecting nodes..."
echo "nodes:" >> "$OUTPUT_FILE"

$KUBECTL get nodes -o json | jq -r '.items[] | @base64' | while read -r node; do
    _jq() {
        echo "$node" | base64 --decode | jq -r "$1"
    }

    name=$(_jq '.metadata.name')
    role=$(_jq '.metadata.labels["node.h-kube.io/role"] // "unknown"')
    location=$(_jq '.metadata.labels["node.h-kube.io/location"] // "unknown"')
    has_nvme=$(_jq '.metadata.labels["storage.h-kube.io/nvme"] // "false"')
    has_bulk=$(_jq '.metadata.labels["storage.h-kube.io/bulk"] // "false"')
    has_gpu=$(_jq '.metadata.labels["capability.h-kube.io/gpu"] // "false"')
    tailscale_ip=$(_jq '.status.addresses[] | select(.type=="InternalIP") | .address')
    cpu=$(_jq '.status.capacity.cpu')
    memory=$(_jq '.status.capacity.memory')
    ready=$(_jq '.status.conditions[] | select(.type=="Ready") | .status')

    cat >> "$OUTPUT_FILE" << EOF
  $name:
    ready: $ready
    role: $role
    location: $location
    tailscale_ip: $tailscale_ip
    resources:
      cpu: $cpu
      memory: $memory
    storage:
      nvme: $has_nvme
      bulk: $has_bulk
    capabilities:
      gpu: $has_gpu

EOF
done

# ==============================================================================
# NAMESPACES
# ==============================================================================
echo "  Collecting namespaces..."
echo "namespaces:" >> "$OUTPUT_FILE"

$KUBECTL get namespaces -o json | jq -r '.items[].metadata.name' | while read -r ns; do
    # Skip system namespaces
    if [[ "$ns" == "kube-system" || "$ns" == "kube-public" || "$ns" == "kube-node-lease" ]]; then
        continue
    fi
    echo "  - $ns" >> "$OUTPUT_FILE"
done
echo "" >> "$OUTPUT_FILE"

# ==============================================================================
# WORKLOADS (Deployments, StatefulSets with nodeSelectors)
# ==============================================================================
echo "  Collecting workloads..."
echo "workloads:" >> "$OUTPUT_FILE"

# Get all deployments and statefulsets
for kind in deployment statefulset; do
    $KUBECTL get $kind --all-namespaces -o json 2>/dev/null | jq -r '.items[] | @base64' | while read -r workload; do
        _jq() {
            echo "$workload" | base64 --decode | jq -r "$1"
        }

        name=$(_jq '.metadata.name')
        namespace=$(_jq '.metadata.namespace')
        replicas=$(_jq '.spec.replicas // 1')
        ready=$(_jq '.status.readyReplicas // 0')

        # Get nodeSelector
        node_selector=$(_jq '.spec.template.spec.nodeSelector // empty')

        # Skip if no interesting nodeSelector
        if [ -z "$node_selector" ] || [ "$node_selector" == "null" ]; then
            node_selector_str="any"
        else
            node_selector_str=$(echo "$node_selector" | jq -r 'to_entries | map("\(.key)=\(.value)") | join(", ")')
        fi

        cat >> "$OUTPUT_FILE" << EOF
  $namespace/$name:
    kind: $kind
    replicas: $ready/$replicas
    nodeSelector: $node_selector_str

EOF
    done
done

# ==============================================================================
# PERSISTENT VOLUME CLAIMS
# ==============================================================================
echo "  Collecting PVCs..."
echo "storage:" >> "$OUTPUT_FILE"
echo "  pvcs:" >> "$OUTPUT_FILE"

$KUBECTL get pvc --all-namespaces -o json 2>/dev/null | jq -r '.items[] | @base64' | while read -r pvc; do
    _jq() {
        echo "$pvc" | base64 --decode | jq -r "$1"
    }

    name=$(_jq '.metadata.name')
    namespace=$(_jq '.metadata.namespace')
    status=$(_jq '.status.phase')
    size=$(_jq '.spec.resources.requests.storage')
    storage_class=$(_jq '.spec.storageClassName // "default"')
    volume_name=$(_jq '.spec.volumeName // "unbound"')

    # Try to get the node where PV is located
    if [ "$volume_name" != "unbound" ] && [ "$volume_name" != "null" ]; then
        node=$($KUBECTL get pv "$volume_name" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}' 2>/dev/null || echo "unknown")
    else
        node="unbound"
    fi

    cat >> "$OUTPUT_FILE" << EOF
    $namespace/$name:
      status: $status
      size: $size
      storageClass: $storage_class
      node: $node

EOF
done

# ==============================================================================
# HELM RELEASES (Flux)
# ==============================================================================
echo "  Collecting Helm releases..."
if $KUBECTL get crd helmreleases.helm.toolkit.fluxcd.io &> /dev/null; then
    echo "  helmReleases:" >> "$OUTPUT_FILE"

    $KUBECTL get helmreleases --all-namespaces -o json 2>/dev/null | jq -r '.items[] | @base64' | while read -r hr; do
        _jq() {
            echo "$hr" | base64 --decode | jq -r "$1"
        }

        name=$(_jq '.metadata.name')
        namespace=$(_jq '.metadata.namespace')
        chart=$(_jq '.spec.chart.spec.chart')
        version=$(_jq '.spec.chart.spec.version // "latest"')
        ready=$(_jq '.status.conditions[] | select(.type=="Ready") | .status' | head -1)

        cat >> "$OUTPUT_FILE" << EOF
    $namespace/$name:
      chart: $chart
      version: $version
      ready: $ready

EOF
    done
else
    echo "  helmReleases: [] # Flux not installed" >> "$OUTPUT_FILE"
fi

echo ""
echo "Generated: $OUTPUT_FILE"
