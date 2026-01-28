#!/bin/bash
#
# tunnel-setup-linux.sh - Set up persistent reverse SSH tunnel to VPS (Linux/systemd)
#
# Usage:
#   ./tunnel-setup-linux.sh <vps_user> <vps_host> [tunnel_port]
#
# Example:
#   ./tunnel-setup-linux.sh deploy my-vps.example.com 2222
#

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <vps_user> <vps_host> [tunnel_port]"
    echo "Example: $0 deploy my-vps.example.com 2222"
    exit 1
fi

VPS_USER="$1"
VPS_HOST="$2"
TUNNEL_PORT="${3:-2222}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_SRC="$SCRIPT_DIR/vaultctl-tunnel.service"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_DEST="$SERVICE_DIR/vaultctl-tunnel.service"

echo "=== Vaultctl Tunnel Setup (Linux) ==="
echo
echo "VPS: $VPS_USER@$VPS_HOST"
echo "Tunnel port: $TUNNEL_PORT (local SSH will be at localhost:$TUNNEL_PORT on VPS)"
echo

# Check SSH connectivity first
echo "Testing SSH connection to VPS..."
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$VPS_USER@$VPS_HOST" "echo 'SSH connection OK'" 2>/dev/null; then
    echo
    echo "ERROR: Cannot connect to $VPS_USER@$VPS_HOST"
    echo
    echo "Make sure:"
    echo "  1. You have SSH key access to the VPS"
    echo "  2. Run: ssh-copy-id $VPS_USER@$VPS_HOST"
    echo "  3. Test: ssh $VPS_USER@$VPS_HOST"
    exit 1
fi
echo "SSH connection OK"
echo

# Configure local username on VPS for headless-vault-cli skill
LOCAL_USER="$(whoami)"
echo "Configuring local username ($LOCAL_USER) on VPS..."
ssh "$VPS_USER@$VPS_HOST" "mkdir -p ~/.config/headless-vault-cli && echo '$LOCAL_USER' > ~/.config/headless-vault-cli/mac-user"
echo "Local username configured"
echo

# Create systemd user directory if needed
mkdir -p "$SERVICE_DIR"

# Generate customized service file
echo "Creating systemd service..."
sed -e "s|REPLACE_WITH_VPS_USER|$VPS_USER|g" \
    -e "s|REPLACE_WITH_VPS_HOST|$VPS_HOST|g" \
    -e "s|REPLACE_WITH_PORT|$TUNNEL_PORT|g" \
    "$SERVICE_SRC" > "$SERVICE_DEST"

# Reload systemd
echo "Reloading systemd..."
systemctl --user daemon-reload

# Stop if already running
systemctl --user stop vaultctl-tunnel 2>/dev/null || true

# Enable and start the service
echo "Enabling and starting service..."
systemctl --user enable --now vaultctl-tunnel

echo
echo "=== Setup Complete ==="
echo
echo "Tunnel service installed and started."
echo
echo "Check status:"
echo "  systemctl --user status vaultctl-tunnel"
echo
echo "View logs:"
echo "  journalctl --user -u vaultctl-tunnel -f"
echo
echo "Test from VPS:"
echo "  ssh -p $TUNNEL_PORT localhost vaultctl tree"
echo
echo "Stop tunnel:"
echo "  systemctl --user stop vaultctl-tunnel"
echo
echo "Start tunnel:"
echo "  systemctl --user start vaultctl-tunnel"
echo
echo "NOTE: For the service to run after logout, enable lingering:"
echo "  sudo loginctl enable-linger $LOCAL_USER"
echo
