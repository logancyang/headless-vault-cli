#!/bin/bash
#
# install.sh - Local installer for headless-vault-cli
#
# USE THIS IF: You cloned the repo manually and want to install from source
#
# For most users, use setup.sh instead (one-line install/update):
#   curl -fsSL https://raw.githubusercontent.com/logancyang/headless-vault-cli/master/setup.sh | bash -s -- <path-to-vault>
#
# This script:
#   1. Copies vaultctl and vaultctl-wrapper to /usr/local/bin
#   2. Creates config file at ~/.config/vaultctl/config
#   3. Prints instructions for SSH and tunnel setup
#
# Usage:
#   ./install.sh <path-to-vault>
#

set -euo pipefail

# Detect OS
OS="$(uname -s)"
case "$OS" in
    Darwin) OS_NAME="macOS" ;;
    Linux)  OS_NAME="Linux" ;;
    *)      echo "Error: Unsupported OS: $OS"; exit 1 ;;
esac

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/vaultctl"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check if we need sudo for /usr/local/bin
if [[ -w "$INSTALL_DIR" ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo "=== Headless Vault CLI - $OS_NAME Setup ==="
echo
echo "This installs the local components for the headless-vault-cli skill."
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
$SUDO cp "$SCRIPT_DIR/vaultctl/vaultctl" "$INSTALL_DIR/vaultctl"
$SUDO cp "$SCRIPT_DIR/vaultctl/vaultctl-wrapper" "$INSTALL_DIR/vaultctl-wrapper"
$SUDO chmod +x "$INSTALL_DIR/vaultctl" "$INSTALL_DIR/vaultctl-wrapper"

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
$SUDO tee "$INSTALL_DIR/vaultctl-wrapper" > /dev/null << 'WRAPPER'
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
$SUDO chmod +x "$INSTALL_DIR/vaultctl-wrapper"

echo
echo "=== Step 1 Complete: vaultctl installed ==="
echo
echo "Test it locally:"
echo "  vaultctl tree"
echo
echo "=== Step 2: SSH Setup ==="
echo
echo "Add your VPS public key to ~/.ssh/authorized_keys with forced-command:"
echo
echo "  command=\"/usr/local/bin/vaultctl-wrapper\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding <VPS_PUBLIC_KEY>"
echo
echo "To get your VPS public key, run this on the VPS:"
echo "  cat ~/.ssh/id_ed25519.pub"
echo
echo "=== Step 3: Start Tunnel ==="
echo

if [[ "$OS" == "Darwin" ]]; then
    # macOS instructions
    echo "Option A - Quick test (manual):"
    echo "  ssh -N -R 2222:localhost:22 user@your-vps.com"
    echo
    echo "Option B - Persistent (auto-reconnect via launchd):"
    echo "  ./setup/tunnel-setup.sh <vps_user> <vps_host>"
else
    # Linux instructions
    echo "Option A - Quick test (manual):"
    echo "  ssh -N -R 2222:localhost:22 user@your-vps.com"
    echo
    echo "Option B - Persistent (auto-reconnect via systemd):"
    echo "  ./setup/tunnel-setup-linux.sh <vps_user> <vps_host>"
fi

echo
echo "=== Step 4: Test from VPS ==="
echo
echo "  ssh -p 2222 localhost vaultctl tree"
echo
echo "If that works, your Moltbot can now access your notes!"
echo
