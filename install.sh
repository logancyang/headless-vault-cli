#!/bin/bash
#
# install.sh - Install vaultctl on macOS
#
# Usage:
#   ./install.sh [VAULT_ROOT]
#
# This script:
#   1. Copies vaultctl and vaultctl-wrapper to /usr/local/bin
#   2. Creates a config file with VAULT_ROOT
#   3. Prints instructions for SSH setup
#

set -euo pipefail

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/vaultctl"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== vaultctl Installer ==="
echo

# Get vault root
if [[ -n "${1:-}" ]]; then
    VAULT_ROOT="$1"
else
    read -p "Enter your vault path (e.g., ~/Notes): " VAULT_ROOT
fi

# Expand ~
VAULT_ROOT="${VAULT_ROOT/#\~/$HOME}"
VAULT_ROOT="$(cd "$VAULT_ROOT" 2>/dev/null && pwd)" || {
    echo "Error: Vault path does not exist: $VAULT_ROOT"
    exit 1
}

echo "Vault root: $VAULT_ROOT"
echo

# Install binaries
echo "Installing vaultctl to $INSTALL_DIR..."
sudo cp "$SCRIPT_DIR/vaultctl/vaultctl" "$INSTALL_DIR/vaultctl"
sudo cp "$SCRIPT_DIR/vaultctl/vaultctl-wrapper" "$INSTALL_DIR/vaultctl-wrapper"
sudo chmod +x "$INSTALL_DIR/vaultctl" "$INSTALL_DIR/vaultctl-wrapper"

# Create config
echo "Creating config at $CONFIG_DIR/config..."
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config" << EOF
# vaultctl configuration
export VAULT_ROOT="$VAULT_ROOT"
export VAULTCTL_PATH="$INSTALL_DIR/vaultctl"
export VAULTCTL_LOG="/tmp/vaultctl.log"
EOF

# Create wrapper that sources config
sudo tee "$INSTALL_DIR/vaultctl-wrapper" > /dev/null << 'WRAPPER'
#!/bin/bash
set -euo pipefail

# Source config
CONFIG_FILE="$HOME/.config/vaultctl/config"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

VAULTCTL_PATH="${VAULTCTL_PATH:-/usr/local/bin/vaultctl}"
LOG_FILE="${VAULTCTL_LOG:-/tmp/vaultctl.log}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

reject() {
    local reason="$1"
    log "REJECTED: $reason (command: ${SSH_ORIGINAL_COMMAND:-<none>})"
    echo '{"error": "command rejected", "reason": "'"$reason"'"}' >&2
    exit 1
}

if [[ -z "${SSH_ORIGINAL_COMMAND:-}" ]]; then
    reject "no command provided"
fi

read -r cmd_name _ <<< "$SSH_ORIGINAL_COMMAND"

if [[ "$cmd_name" != "vaultctl" ]]; then
    reject "only vaultctl commands allowed"
fi

log "ALLOWED: $SSH_ORIGINAL_COMMAND"

args="${SSH_ORIGINAL_COMMAND#vaultctl}"
exec "$VAULTCTL_PATH" $args
WRAPPER
sudo chmod +x "$INSTALL_DIR/vaultctl-wrapper"

echo
echo "=== Installation Complete ==="
echo
echo "Test it:"
echo "  export VAULT_ROOT=\"$VAULT_ROOT\""
echo "  vaultctl tree"
echo
echo "=== SSH Setup (on this Mac) ==="
echo
echo "To allow remote access, add this to ~/.ssh/authorized_keys:"
echo
echo "  command=\"/usr/local/bin/vaultctl-wrapper\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding <VPS_PUBLIC_KEY>"
echo
echo "Replace <VPS_PUBLIC_KEY> with the public key from your VPS."
echo
echo "=== Reverse Tunnel (run on this Mac) ==="
echo
echo "  ssh -N -R 2222:localhost:22 user@your-vps.com"
echo
echo "Then from VPS, test with:"
echo "  ssh -p 2222 localhost vaultctl tree"
echo
