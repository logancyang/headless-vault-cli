#!/bin/bash
#
# setup.sh - One-line installer for headless-vault-cli
#
# USE THIS IF: You want to install or update with a single command (recommended)
#
# This script:
#   1. Downloads the repo to ~/.local/share/headless-vault-cli (or updates if exists)
#   2. Runs install.sh to copy binaries and create config
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/logancyang/headless-vault-cli/master/setup.sh | bash -s -- <path-to-vault>
#
# Replace <path-to-vault> with your notes folder (e.g. ~/Notes, ~/Documents/MyVault)
# Same command works for both fresh install and updates.
#

set -euo pipefail

REPO_URL="https://github.com/logancyang/headless-vault-cli.git"
INSTALL_DIR="${HOME}/.local/share/headless-vault-cli"

# Get vault path from argument
VAULT_PATH="${1:-}"
if [[ -z "$VAULT_PATH" ]]; then
    echo "Usage: setup.sh <vault-path>"
    echo "Example: setup.sh ~/Notes"
    exit 1
fi

# Expand ~
VAULT_PATH="${VAULT_PATH/#\~/$HOME}"

echo "=== Headless Vault CLI Setup ==="
echo

# Check for git
if ! command -v git &> /dev/null; then
    echo "Error: git is required but not installed."
    exit 1
fi

# Clone or update repo
if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "Updating existing installation..."
    git -C "$INSTALL_DIR" pull --quiet
else
    echo "Downloading headless-vault-cli..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

# Run the install script
echo
exec "$INSTALL_DIR/install.sh" "$VAULT_PATH"
