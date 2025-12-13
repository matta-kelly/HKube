#!/bin/bash
set -e

if [ ! -f ".vault_password" ]; then
    echo "Creating vault password..."
    openssl rand -base64 32 > .vault_password
    chmod 600 .vault_password
    echo "Created .vault_password"
else
    echo "Vault password exists"
fi
