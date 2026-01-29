# Molt Note Connector

Remote Markdown vault read/edit skill for Moltbot via `vaultctl`.

## Project Overview

This project implements a Moltbot skill that allows a VPS-hosted bot to securely read and edit Markdown files on a local machine (macOS or Linux). Uses reverse SSH tunnel with forced-command restriction for security.

## Architecture

```
┌─────────────────┐     reverse tunnel     ┌─────────────────┐
│  VPS (Moltbot)  │◄──────────────────────►│  Local Machine  │
│                 │   localhost:<PORT>      │  (Mac/Linux)    │
│  skill calls:   │                        │  vaultctl       │
│  ssh vaultctl   │────────────────────────►│  (forced cmd)   │
│  <cmd> <args>   │                        │                 │
└─────────────────┘                        └─────────────────┘
                                                   │
                                                   ▼
                                            VAULT_ROOT/
                                            └── *.md files
```

## Execution Flow

1. **Mac → VPS**: Persistent reverse tunnel exposes Mac SSH as `localhost:<MAC_TUNNEL_PORT>`
2. **VPS → Mac**: All operations run as: `ssh -p <MAC_TUNNEL_PORT> localhost vaultctl <subcommand> <args>`
3. **vaultctl** enforces: sandboxing, sha256 concurrency checks, patch-based edits

## Security Model

- **Forced-command**: VPS SSH key in `~/.ssh/authorized_keys` restricted to only execute `vaultctl`
- **No interactive shell**: Bot cannot run `rm`, `curl`, or arbitrary commands
- **Vault sandboxing**: All paths validated inside `VAULT_ROOT`

## vaultctl Commands (v0)

```bash
vaultctl tree [--depth N] [--all]              # List vault structure
vaultctl resolve (--path P | --title T)        # Resolve note path
vaultctl info <path>                           # Get file metadata
vaultctl read <path>                           # Read entire note
vaultctl create <path> <content>               # Create new note
vaultctl append <path> <content>               # Append to note
vaultctl set-root <path>                       # Change vault root directory
```

### Future commands (v1+)
- `outline`, `search`, `read-range`, `apply-patch`

## Project Structure

```
vaultctl/
├── vaultctl           # Main CLI (Python)
└── vaultctl-wrapper   # SSH forced-command wrapper (Bash)
setup/
├── tunnel-setup.sh          # macOS tunnel setup (launchd)
├── tunnel-setup-linux.sh    # Linux tunnel setup (systemd)
├── com.vaultctl.tunnel.plist    # macOS launchd service template
└── vaultctl-tunnel.service      # Linux systemd service template
install.sh             # Installation script (macOS + Linux)
```

## Tech Stack

- **vaultctl**: Python 3 CLI with JSON output
- **vaultctl-wrapper**: Bash script for SSH forced-command
- **SSH**: Reverse tunnel + forced-command restriction

## Quick Start

```bash
# Install (sets VAULT_ROOT automatically)
./install.sh ~/Notes

# Test locally
vaultctl tree

# Change vault root later
vaultctl set-root ~/NewNotes

# SSH setup (add to ~/.ssh/authorized_keys on Mac)
command="/usr/local/bin/vaultctl-wrapper",no-port-forwarding,no-X11-forwarding,no-agent-forwarding <VPS_KEY>

# Start reverse tunnel (on Mac)
ssh -N -R 2222:localhost:22 user@vps

# Test from VPS
ssh -p 2222 localhost vaultctl tree
```

## Development Notes

- See `DESIGN_DOC.md` for full requirements
- See `TODO.md` for implementation status
- All output is JSON to stdout, errors to stderr
- Exit codes: 0=success, 1=user error, 2=system error
