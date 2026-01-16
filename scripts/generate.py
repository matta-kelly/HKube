#!/usr/bin/env python3
"""
Generate Ansible inventory and other outputs from config.yaml + secrets.env.

Usage: ./scripts/generate.py
"""

import os
import yaml
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
CONFIG_DIR = PROJECT_ROOT / "config"
CONFIG_FILE = CONFIG_DIR / "config.yaml"
SECRETS_FILE = CONFIG_DIR / "secrets.env"
OUTPUT_DIR = PROJECT_ROOT / "generated"
INVENTORY_FILE = OUTPUT_DIR / "inventory.yml"


def load_config():
    """Load config.yaml."""
    with open(CONFIG_FILE) as f:
        return yaml.safe_load(f)


def load_secrets():
    """Load secrets.env as dict."""
    secrets = {}
    if SECRETS_FILE.exists():
        with open(SECRETS_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    secrets[key] = value.strip('"')
    return secrets


def expand_path(path):
    """Expand ~ in paths."""
    return os.path.expanduser(path)


def generate_inventory(config, secrets):
    """Generate Ansible inventory.yml."""
    identity = config["identity"]
    versions = config["versions"]
    ssh_keys = config["ssh_keys"]
    nodes = config["nodes"]

    inventory = {
        "all": {
            "vars": {
                "admin_user": identity["admin_user"],
                "domain": identity["domain"],
                "mesh_domain": f"mesh.{identity['domain']}",
                "headscale_domain": f"headscale.{identity['domain']}",
                "kube_domain": f"kube.{identity['domain']}",
                "github_user": identity["github_user"],
                "github_repo": identity["github_repo"],
                "github_branch": identity["github_branch"],
                "k3s_version": versions["k3s"],
                "sops_version": versions["sops"],
                "headscale_authkey": secrets.get("HEADSCALE_AUTHKEY", ""),
            },
            "children": {}
        }
    }

    # Group nodes by role
    groups = {
        "anchor": [],
        "control_planes": [],
        "home_servers": [],
        "home_workers": [],
    }

    for name, node in nodes.items():
        role = node.get("role", "other")
        node_type = node.get("type", "home")

        if role == "headscale":
            groups["anchor"].append((name, node))
        elif role == "k3s-server" and node_type == "cloud":
            groups["control_planes"].append((name, node))
        elif role == "k3s-server" and node_type == "home":
            groups["home_servers"].append((name, node))
        elif role == "k3s-agent":
            groups["home_workers"].append((name, node))

    # Build inventory groups
    for group_name, group_nodes in groups.items():
        if not group_nodes:
            continue

        inventory["all"]["children"][group_name] = {"hosts": {}}

        for name, node in group_nodes:
            ssh_key_name = node.get("ssh_key", "personal")
            ssh_key_path = expand_path(ssh_keys.get(ssh_key_name, ssh_keys["personal"]))

            host_entry = {
                "ansible_host": node.get("tailscale_ip") or node["ip"],
                "ansible_user": node.get("ssh_user", identity["admin_user"]),
                "ansible_ssh_private_key_file": ssh_key_path,
                "tailscale_hostname": node.get("tailscale_hostname", name),
            }

            # Add firewall ports if defined
            if "firewall_ports" in node:
                host_entry["firewall_allow_ports"] = node["firewall_ports"]

            # Add headscale version for anchor
            if node.get("role") == "headscale":
                host_entry["headscale_version"] = versions["headscale"]
                # Add OIDC configuration
                oidc_config = config.get("oidc", {})
                host_entry["oidc_enabled"] = oidc_config.get("enabled", False)
                host_entry["oidc_client_id"] = secrets.get("OIDC_CLIENT_ID", "")
                host_entry["oidc_client_secret"] = secrets.get("OIDC_CLIENT_SECRET", "")
                host_entry["oidc_allowed_groups"] = oidc_config.get("allowed_groups", [])

            # Build k3s node labels from config
            # These get applied by Ansible during bootstrap
            if node.get("role") in ("k3s-server", "k3s-agent"):
                k3s_labels = {}

                # Add node role label (strip k3s- prefix for cleaner labels)
                role = node["role"].replace("k3s-", "")
                k3s_labels["node.h-kube.io/role"] = role
                k3s_labels["node.h-kube.io/type"] = node.get("type", "home")

                # Add custom labels
                for key, value in node.get("labels", {}).items():
                    k3s_labels[f"node.h-kube.io/{key}"] = str(value)

                # Add storage labels
                for key, value in node.get("storage", {}).items():
                    k3s_labels[f"storage.h-kube.io/{key}"] = str(value).lower()

                # Add capability labels
                for key, value in node.get("capabilities", {}).items():
                    k3s_labels[f"capability.h-kube.io/{key}"] = str(value).lower()

                host_entry["k3s_labels"] = k3s_labels

            inventory["all"]["children"][group_name]["hosts"][name] = host_entry

    return inventory


def write_inventory(inventory):
    """Write inventory.yml."""
    OUTPUT_DIR.mkdir(exist_ok=True)

    header = """\
# ==============================================================================
# Ansible Inventory (GENERATED - DO NOT EDIT)
# ==============================================================================
# Generated from: config/config.yaml + config/secrets.env
# Regenerate with: make generate
# ==============================================================================

"""
    with open(INVENTORY_FILE, "w") as f:
        f.write(header)
        yaml.dump(inventory, f, default_flow_style=False, sort_keys=False)

    print(f"Generated: {INVENTORY_FILE}")


def main():
    print("Loading config.yaml...")
    config = load_config()

    print("Loading secrets.env...")
    secrets = load_secrets()

    print("Generating inventory...")
    inventory = generate_inventory(config, secrets)
    write_inventory(inventory)

    print("\nDone!")


if __name__ == "__main__":
    main()
