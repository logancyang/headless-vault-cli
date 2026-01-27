# clawd-note-connector

Let your AI assistant read and edit your local notes — securely.

## What is this?

If you run an AI bot on a server (like Clawdbot), it can't normally access files on your laptop. This tool creates a secure bridge so your bot can read and write Markdown notes in a specific folder on your Mac.

**How it works:** Your Mac connects to your server and keeps a secure channel open. The bot can only run a specific set of commands (`vaultctl`) — it cannot access other files or run arbitrary programs.

## Note to Obsidian Users
When running clawdbot on a remote server, tools like the bundled obsidian-cli doesn't fully work because many of its operations require the Obsidian GUI app installed on that remote machine. This note-connector is the way around. It allows the remote clawdbot operate on your local folder, no Obsidian app or vault required, simply a folder and markdown files!

## Features

- **Safe by design**: Bot can only access your notes folder, nothing else
- **No network hassles**: Works even if your Mac is on WiFi, behind a router, or on a VPN
- **Automatic backups**: Creates a backup before any edit
- **Simple commands**: `tree`, `read`, `create`, `append`

## Quick Start

Setup requires two parts: **VPS** (where Clawdbot runs) and **Mac** (where your notes live).

### 1. Install plugin on VPS

```bash
clawdhub install note-connector
```

### 2. Install on Mac

```bash
git clone https://github.com/anthropics/clawd-note-connector.git
cd clawd-note-connector
./install.sh ~/Notes
```

### 3. Test locally (on Mac)

```bash
export VAULT_ROOT=~/Notes
vaultctl tree
vaultctl read "Projects/Plan.md"
```

### 4. Set up SSH access

This step lets your VPS connect to your Mac, but *only* to run vaultctl commands.

**On your VPS**, get the public key:
```bash
cat ~/.ssh/id_ed25519.pub
```

If you get "No such file", generate a key first:
```bash
ssh-keygen -t ed25519 -C "clawdbot"
# Press Enter 3 times to accept defaults (no passphrase)
cat ~/.ssh/id_ed25519.pub
```

You'll see something like:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@vps
```

**On your Mac**, open (or create) the authorized_keys file:
```bash
vim ~/.ssh/authorized_keys
```

Add this line (all on one line), replacing `<PASTE_VPS_KEY_HERE>` with the key you copied:
```
command="/usr/local/bin/vaultctl-wrapper",no-port-forwarding,no-X11-forwarding,no-agent-forwarding <PASTE_VPS_KEY_HERE>
```

So the full line looks like:
```
command="/usr/local/bin/vaultctl-wrapper",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@vps
```

Save and exit (`:wq` then Enter).

**Important:** Fix permissions (SSH ignores the file if others can read it):
```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

**What this does:** The `command=` prefix restricts this key so it can *only* run vaultctl — even if someone has the key, they can't get a shell or run other commands.

### 5. Start reverse tunnel (on Mac)

**Option A: Manual (for testing)**
```bash
ssh -N -R 2222:localhost:22 user@your-vps.com
```

**Option B: Persistent (auto-reconnect via launchd)**
```bash
./setup/tunnel-setup.sh <vps_user> <vps_host> [port]
# Example:
./setup/tunnel-setup.sh deploy my-vps.example.com 2222
```

This installs a launchd service that:
- Starts on login
- Auto-reconnects if connection drops
- Logs to `/tmp/vaultctl-tunnel.log`

### 6. Test from VPS

```bash
ssh -p 2222 <mac-username>@localhost vaultctl tree
```

Replace `<mac-username>` with your Mac username. To find it, run `whoami` on your Mac.

Example:
```bash
ssh -p 2222 logan@localhost vaultctl tree
```

If that works, your Clawdbot can now access your notes!

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

### Changing your vault folder

The vault path is stored in `~/.config/vaultctl/config` on your Mac.

**Option 1: Re-run the installer**
```bash
./install.sh ~/NewNotesFolder
```

**Option 2: Edit the config directly**
```bash
vim ~/.config/vaultctl/config
# Change VAULT_ROOT to your new path
```

### Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VAULT_ROOT` | Path to vault directory | Required |
| `VAULTCTL_PATH` | Path to vaultctl binary | `/usr/local/bin/vaultctl` |
| `VAULTCTL_LOG` | Log file for wrapper | `/tmp/vaultctl.log` |

Config file location: `~/.config/vaultctl/config`

## Requirements

- macOS (tested on Ventura+)
- Python 3.9+
- SSH server enabled

## License

MIT License - see [LICENSE](LICENSE)
