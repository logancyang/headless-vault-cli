---
name: vault-controller
description: Read and edit Markdown notes on a remote Mac via SSH tunnel.
homepage: https://github.com/logancyang/vault-controller
metadata: {"clawdbot":{"emoji":"🗄️"}}
---

# Vault Controller

Access Markdown notes on a local Mac from this remote Clawdbot via SSH tunnel.

## Available Commands

You have access to these commands ONLY. Do not attempt commands not listed here (no rename, delete, move, or edit commands exist).

| Command | Description |
|---------|-------------|
| `tree` | List vault directory structure |
| `resolve` | Find note by path or title |
| `info` | Get file metadata (lines, bytes, sha256, mtime) |
| `read` | Read note content |
| `create` | Create a NEW note (fails if file exists) |
| `append` | Append content to EXISTING note (creates backup) |
| `set-root` | Set vault root directory |

## How to Run Commands

All commands are executed via SSH:
```bash
ssh -4 -p ${VAULT_SSH_PORT:-2222} ${VAULT_SSH_USER}@${VAULT_SSH_HOST:-localhost} vaultctl <command> [args]
```

Always use `-4` to force IPv4 (avoids IPv6 timeout issues).

## Command Reference

### tree - List vault structure
```bash
ssh -4 -p 2222 ${VAULT_SSH_USER}@localhost vaultctl tree
ssh -4 -p 2222 ${VAULT_SSH_USER}@localhost vaultctl tree --depth 2
ssh -4 -p 2222 ${VAULT_SSH_USER}@localhost vaultctl tree --all
```
Options:
- `--depth N` - Maximum depth to traverse
- `--all` - Include all files, not just .md

### resolve - Find note by path or title
```bash
ssh -4 -p 2222 ${VAULT_SSH_USER}@localhost vaultctl resolve --title "Meeting Notes"
ssh -4 -p 2222 ${VAULT_SSH_USER}@localhost vaultctl resolve --path "Projects/Plan.md"
```

### info - Get file metadata
```bash
ssh -4 -p 2222 ${VAULT_SSH_USER}@localhost vaultctl info "Projects/Plan.md"
```
Returns JSON: `{"path": "...", "lines": N, "bytes": N, "sha256": "...", "mtime": N}`

### read - Read note content
```bash
ssh -4 -p 2222 ${VAULT_SSH_USER}@localhost vaultctl read "Projects/Plan.md"
```
Returns JSON: `{"path": "...", "content": "..."}`

### create - Create a NEW note
**IMPORTANT**: Use `--base64` flag with BOTH path AND content base64 encoded. This is required for paths/content with spaces or special characters.

```bash
ssh -4 -p 2222 ${VAULT_SSH_USER}@localhost vaultctl create <base64_path> <base64_content> --base64
```

Example to create "Notes/Morning Brief.md" with content "# Hello\n\nWorld":
```bash
# Encode path: echo -n "Notes/Morning Brief.md" | base64 → Tm90ZXMvTW9ybmluZyBCcmllZi5tZA==
# Encode content: echo -n "# Hello\n\nWorld" | base64 → IyBIZWxsbwoKV29ybGQ=
ssh -4 -p 2222 ${VAULT_SSH_USER}@localhost vaultctl create Tm90ZXMvTW9ybmluZyBCcmllZi5tZA== IyBIZWxsbwoKV29ybGQ= --base64
```

- Creates parent directories automatically
- Fails if file already exists (use `append` to add to existing files)
- File must have `.md` extension

### append - Append to EXISTING note
```bash
ssh -4 -p 2222 ${VAULT_SSH_USER}@localhost vaultctl append <base64_path> <base64_content> --base64
```

- Creates a timestamped backup before modifying
- Fails if file does not exist (use `create` for new files)

### set-root - Set vault root directory
```bash
ssh -4 -p 2222 ${VAULT_SSH_USER}@localhost vaultctl set-root /path/to/vault
```

## What You CANNOT Do

These operations are NOT supported:
- **Rename** files or folders
- **Delete** files or folders
- **Move** files between folders
- **Edit** specific parts of a file (only append to end)
- **Create** folders without a file (folders are created automatically with `create`)

## Environment Variables

Auto-configured by tunnel-setup.sh:
- `VAULT_SSH_USER` - Mac username (auto-detected)
- `VAULT_SSH_PORT` - Tunnel port (default: 2222)
- `VAULT_SSH_HOST` - Tunnel host (default: localhost)

## Tips

- Always run `vaultctl tree` first to see what notes exist
- Use `vaultctl resolve --title "..."` to find a note by name
- All output is JSON
- The Mac must be online with tunnel running
- **For create/append**: ALWAYS base64 encode BOTH path AND content with `--base64` flag
