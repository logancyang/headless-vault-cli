#!/bin/bash
#
# vault.sh - Clawdbot skill wrapper for vaultctl
#
# This script is called by Clawdbot to execute vault operations
# on the remote Mac via SSH tunnel.
#
# Usage:
#   ./vault.sh <command> [args...]
#
# Environment:
#   VAULT_SSH_PORT  - SSH port for tunnel (default: 2222)
#   VAULT_SSH_HOST  - SSH host (default: localhost)
#

set -euo pipefail

VAULT_SSH_PORT="${VAULT_SSH_PORT:-2222}"
VAULT_SSH_HOST="${VAULT_SSH_HOST:-localhost}"
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new"

# Run vaultctl command on remote Mac
run_vaultctl() {
    ssh $SSH_OPTS -p "$VAULT_SSH_PORT" "$VAULT_SSH_HOST" vaultctl "$@"
}

# Check if tunnel is up
check_tunnel() {
    if ! ssh $SSH_OPTS -p "$VAULT_SSH_PORT" "$VAULT_SSH_HOST" vaultctl tree --depth 0 >/dev/null 2>&1; then
        echo '{"error": "tunnel_down", "message": "Cannot reach Mac. Is the tunnel running?"}' >&2
        exit 1
    fi
}

cmd="${1:-}"
shift || true

case "$cmd" in
    tree)
        args=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                depth=*) args+=(--depth "${1#depth=}") ;;
                all=true) args+=(--all) ;;
            esac
            shift
        done
        run_vaultctl tree "${args[@]}"
        ;;

    resolve)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                path=*) run_vaultctl resolve --path "${1#path=}"; exit ;;
                title=*) run_vaultctl resolve --title "${1#title=}"; exit ;;
            esac
            shift
        done
        echo '{"error": "missing_param", "message": "Specify path= or title="}' >&2
        exit 1
        ;;

    info)
        path=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                path=*) path="${1#path=}" ;;
            esac
            shift
        done
        if [[ -z "$path" ]]; then
            echo '{"error": "missing_param", "message": "path= is required"}' >&2
            exit 1
        fi
        run_vaultctl info "$path"
        ;;

    read)
        path=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                path=*) path="${1#path=}" ;;
            esac
            shift
        done
        if [[ -z "$path" ]]; then
            echo '{"error": "missing_param", "message": "path= is required"}' >&2
            exit 1
        fi
        run_vaultctl read "$path"
        ;;

    create)
        path=""
        content=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                path=*) path="${1#path=}" ;;
                content=*) content="${1#content=}" ;;
            esac
            shift
        done
        if [[ -z "$path" || -z "$content" ]]; then
            echo '{"error": "missing_param", "message": "path= and content= are required"}' >&2
            exit 1
        fi
        run_vaultctl create "$path" "$content"
        ;;

    append)
        path=""
        content=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                path=*) path="${1#path=}" ;;
                content=*) content="${1#content=}" ;;
            esac
            shift
        done
        if [[ -z "$path" || -z "$content" ]]; then
            echo '{"error": "missing_param", "message": "path= and content= are required"}' >&2
            exit 1
        fi
        run_vaultctl append "$path" "$content"
        ;;

    check)
        check_tunnel
        echo '{"status": "ok", "message": "Tunnel is up"}'
        ;;

    *)
        echo '{"error": "unknown_command", "message": "Unknown command: '"$cmd"'", "available": ["tree", "resolve", "info", "read", "create", "append", "check"]}' >&2
        exit 1
        ;;
esac
