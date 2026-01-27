# clawd-note-connector

Remote Markdown vault access for AI assistants via SSH.

Allows a VPS-hosted bot (like Clawdbot) to securely read and write Markdown files on your local Mac, even behind NAT. Uses reverse SSH tunnel with forced-command restriction for security.

## Features

- **Sandboxed access**: All operations restricted to your vault directory
- **SSH security**: Forced-command prevents arbitrary command execution
- **Simple CLI**: JSON output for easy integration
- **Backup on write**: Automatic timestamped backups before modifications

## Quick Start

### 1. Install on Mac

```bash
git clone https://github.com/anthropics/clawd-note-connector.git
cd clawd-note-connector
./install.sh ~/Notes
```

### 2. Test locally

```bash
export VAULT_ROOT=~/Notes
vaultctl tree
vaultctl read "Projects/Plan.md"
```

### 3. Set up SSH access (for remote bot)

Add your VPS public key to `~/.ssh/authorized_keys` on Mac:

```
command="/usr/local/bin/vaultctl-wrapper",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA... bot@vps
```

### 4. Start reverse tunnel (on Mac)

```bash
ssh -N -R 2222:localhost:22 user@your-vps.com
```

### 5. Test from VPS

```bash
ssh -p 2222 localhost vaultctl tree
```

## Commands

| Command | Description | Example |
|---------|-------------|---------|
| `tree` | List vault structure | `vaultctl tree --depth 2` |
| `resolve` | Find note by path or title | `vaultctl resolve --title "Meeting"` |
| `info` | Get file metadata | `vaultctl info Projects/Plan.md` |
| `read` | Read entire note | `vaultctl read Projects/Plan.md` |
| `create` | Create new note | `vaultctl create Notes/New.md "# Title"` |
| `append` | Append to note | `vaultctl append Notes/Log.md "Entry"` |

All commands output JSON to stdout. Errors go to stderr with exit code 1 (user error) or 2 (system error).

## Example Output

```bash
$ vaultctl tree
{"tree": [{"path": "Notes", "type": "dir"}, {"path": "Notes/Ideas.md", "type": "file"}, {"path": "Projects", "type": "dir"}, {"path": "Projects/Plan.md", "type": "file"}]}

$ vaultctl info Projects/Plan.md
{"path": "/Users/me/Notes/Projects/Plan.md", "lines": 42, "bytes": 1337, "sha256": "abc123...", "mtime": 1706000000}

$ vaultctl read Projects/Plan.md
{"path": "/Users/me/Notes/Projects/Plan.md", "content": "# Project Plan\n\n..."}
```

## Architecture

```
┌─────────────────┐     reverse tunnel     ┌─────────────────┐
│  VPS (Bot)      │◄──────────────────────►│  Mac (Local)    │
│                 │   localhost:2222        │                 │
│  ssh vaultctl   │────────────────────────►│  vaultctl       │
│  <cmd> <args>   │                        │  (forced cmd)   │
└─────────────────┘                        └─────────────────┘
                                                   │
                                                   ▼
                                            ~/Notes/
                                            └── *.md files
```

## Security

- **Forced-command**: SSH key can only run `vaultctl`, not arbitrary commands
- **Path sandboxing**: All paths validated inside `VAULT_ROOT`
- **No shell access**: Bot cannot run `rm`, `curl`, etc.
- **Backups**: Writes create timestamped backups automatically

## Configuration

Environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `VAULT_ROOT` | Path to vault directory | Required |
| `VAULTCTL_PATH` | Path to vaultctl binary | `/usr/local/bin/vaultctl` |
| `VAULTCTL_LOG` | Log file for wrapper | `/tmp/vaultctl.log` |

## Requirements

- macOS (tested on Ventura+)
- Python 3.9+
- SSH server enabled

## License

MIT License - see [LICENSE](LICENSE)
