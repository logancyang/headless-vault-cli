#!/bin/bash
#
# tunnel-setup.sh - Set up persistent reverse SSH tunnel to VPS
#
# Usage:
#   ./tunnel-setup.sh <vps_user> <vps_host> [tunnel_port]
#
# Example:
#   ./tunnel-setup.sh deploy my-vps.example.com 2222
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
PLIST_SRC="$SCRIPT_DIR/com.vaultctl.tunnel.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/com.vaultctl.tunnel.plist"

echo "=== Vaultctl Tunnel Setup ==="
echo
echo "VPS: $VPS_USER@$VPS_HOST"
echo "Tunnel port: $TUNNEL_PORT (Mac SSH will be at localhost:$TUNNEL_PORT on VPS)"
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

# Create LaunchAgents directory if needed
mkdir -p "$HOME/Library/LaunchAgents"

# Generate customized plist
echo "Creating launchd plist..."
sed -e "s|REPLACE_WITH_VPS_USER|$VPS_USER|g" \
    -e "s|REPLACE_WITH_VPS_HOST|$VPS_HOST|g" \
    -e "s|2222:localhost:22|$TUNNEL_PORT:localhost:22|g" \
    "$PLIST_SRC" > "$PLIST_DEST"

# Unload if already loaded
launchctl unload "$PLIST_DEST" 2>/dev/null || true

# Load the new plist
echo "Loading launchd service..."
launchctl load "$PLIST_DEST"

echo
echo "=== Setup Complete ==="
echo
echo "Tunnel service installed and started."
echo
echo "Check status:"
echo "  launchctl list | grep vaultctl"
echo
echo "View logs:"
echo "  tail -f /tmp/vaultctl-tunnel.log"
echo
echo "Test from VPS:"
echo "  ssh -p $TUNNEL_PORT localhost vaultctl tree"
echo
echo "Stop tunnel:"
echo "  launchctl unload ~/Library/LaunchAgents/com.vaultctl.tunnel.plist"
echo
echo "Start tunnel:"
echo "  launchctl load ~/Library/LaunchAgents/com.vaultctl.tunnel.plist"
echo
