#!/bin/bash
# ==============================================================================
# Document Network State
# ==============================================================================
# Queries Tailscale mesh and generates network-status.yaml.
# This is DOCUMENTATION of current network state.
#
# Usage: make network-status
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_ROOT/generated"
OUTPUT_FILE="$OUTPUT_DIR/network-status.yaml"

mkdir -p "$OUTPUT_DIR"

# Check if tailscale is available
if ! command -v tailscale &> /dev/null; then
    echo "Error: tailscale not installed"
    exit 1
fi

echo "Documenting network topology..."

# Get tailscale status as JSON
TS_STATUS=$(tailscale status --json 2>/dev/null)

if [ -z "$TS_STATUS" ]; then
    echo "Error: Could not get tailscale status"
    exit 1
fi

# Start building the YAML
cat > "$OUTPUT_FILE" << 'HEADER'
# ==============================================================================
# Network Status (GENERATED - DO NOT EDIT)
# ==============================================================================
# Generated from: tailscale status
# Regenerate with: make network-status
# ==============================================================================

HEADER

# Extract self info
SELF_HOSTNAME=$(echo "$TS_STATUS" | jq -r '.Self.HostName')
SELF_IP=$(echo "$TS_STATUS" | jq -r '.Self.TailscaleIPs[0]')
SELF_OS=$(echo "$TS_STATUS" | jq -r '.Self.OS')
SELF_ONLINE=$(echo "$TS_STATUS" | jq -r '.Self.Online')

cat >> "$OUTPUT_FILE" << EOF
self:
  hostname: $SELF_HOSTNAME
  tailscale_ip: $SELF_IP
  os: $SELF_OS
  online: $SELF_ONLINE

mesh:
  control_url: $(echo "$TS_STATUS" | jq -r '.ControlURL // "unknown"')

peers:
EOF

# Parse each peer
echo "$TS_STATUS" | jq -r '.Peer | to_entries[] | @base64' 2>/dev/null | while read -r peer; do
    _jq() {
        echo "$peer" | base64 --decode | jq -r ".value$1"
    }

    hostname=$(_jq '.HostName')
    tailscale_ip=$(_jq '.TailscaleIPs[0]')
    os=$(_jq '.OS')
    online=$(_jq '.Online')
    last_seen=$(_jq '.LastSeen')

    # Skip if no hostname
    [ "$hostname" = "null" ] && continue

    cat >> "$OUTPUT_FILE" << EOF
  $hostname:
    tailscale_ip: $tailscale_ip
    os: $os
    online: $online
    last_seen: $last_seen
EOF
done

# Add connectivity check section
cat >> "$OUTPUT_FILE" << EOF

connectivity:
EOF

# Test connectivity to known nodes from config
if [ -f "$PROJECT_ROOT/config/config.yaml" ]; then
    echo "  # Ping tests to configured nodes" >> "$OUTPUT_FILE"

    # Use venv python if available, otherwise try system python
    if [ -f "$PROJECT_ROOT/.venv/bin/python" ]; then
        PYTHON="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON="python3"
    fi

    # Extract node IPs and test connectivity
    $PYTHON << 'PYEOF' >> "$OUTPUT_FILE"
import yaml
import subprocess
import os

config_path = os.environ.get('PROJECT_ROOT', '.') + '/config/config.yaml'
try:
    with open(config_path) as f:
        config = yaml.safe_load(f)

    nodes = config.get('nodes', {})
    for name, node in nodes.items():
        # Prefer tailscale_ip for mesh nodes, fall back to regular ip
        ts_ip = node.get('tailscale_ip')
        local_ip = node.get('ip')
        test_ip = ts_ip or local_ip

        if test_ip and test_ip != '0.0.0.0':
            # Quick ping test (1 packet, 1 second timeout)
            result = subprocess.run(
                ['ping', '-c', '1', '-W', '1', test_ip],
                capture_output=True
            )
            reachable = 'true' if result.returncode == 0 else 'false'
            print(f"  {name}:")
            if ts_ip:
                print(f"    tailscale_ip: {ts_ip}")
            if local_ip and local_ip != '0.0.0.0':
                print(f"    local_ip: {local_ip}")
            print(f"    reachable: {reachable}")
except Exception as e:
    print(f"  # Error reading config: {e}")
PYEOF
fi

echo ""
echo "Generated: $OUTPUT_FILE"
echo ""
cat "$OUTPUT_FILE"
