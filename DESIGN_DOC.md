# Clawdbot Skill MVP: Remote Read/Edit of Local Markdown Vault (macOS)

## Remote Execution Architecture

### Goal

Allow the VPS-hosted bot to run a restricted set of shell-like commands on the local macOS machine (where the vault lives) with minimal setup, without adopting Clawdbot Nodes.

### Approach

1. **Connectivity**: The Mac maintains a reverse SSH tunnel to the VPS so the VPS can reach the Mac even behind NAT / changing networks.

2. **Security**: The Mac uses an SSH key that is restricted with a **forced command** so the VPS cannot open an interactive shell or run arbitrary commands.

3. **Command surface**: The forced command dispatches to a single local helper executable named `vaultctl` ("vault control"), which implements the vault primitives (`info`, `outline`, `search`, `read-range`, `apply-patch`) safely inside `VAULT_ROOT`.

### Execution Flow

```
┌─────────────────┐                        ┌─────────────────┐
│  Mac (Local)    │   reverse SSH tunnel   │  VPS (Clawdbot) │
│                 │ ─────────────────────► │                 │
│  SSH server     │   exposes Mac as       │  localhost:PORT │
│  + vaultctl     │   localhost:<PORT>     │                 │
└─────────────────┘                        └─────────────────┘
                                                   │
                                                   │ skill executes:
                                                   │ ssh -p <PORT> localhost vaultctl <cmd> <args>
                                                   ▼
                                           ┌─────────────────┐
                                           │  vaultctl       │
                                           │  enforces:      │
                                           │  - sandboxing   │
                                           │  - sha256 check │
                                           │  - backups      │
                                           │  - patch edits  │
                                           └─────────────────┘
```

1. **Mac → VPS**: Persistent reverse tunnel exposes Mac SSH as `localhost:<MAC_TUNNEL_PORT>` on the VPS.
2. **VPS (skill) → Mac**: All operations run as:
   ```
   ssh -p <MAC_TUNNEL_PORT> localhost vaultctl <subcommand> <args>
   ```
3. **vaultctl** enforces:
   - Sandboxing to `VAULT_ROOT`
   - Concurrency checks via sha256
   - Backups before writes
   - Patch-based edits (no whole-file rewrite by default)

### Forced-Command Restriction (Security Contract)

In `~/.ssh/authorized_keys` on the Mac, the VPS key is configured to:
- Deny interactive shell
- Only allow executing `vaultctl …`

Example `authorized_keys` entry:
```
command="/usr/local/bin/vaultctl-wrapper",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA... vps-bot-key
```

This ensures the bot **cannot** run `rm`, `curl`, or any other arbitrary command on the Mac, even though it is using SSH.

### Why This Path

- Fewer moving parts than Node pairing/approvals
- Tool-agnostic: works for Clawdbot today, and can be reused by other clients that can run SSH
- Keeps the "shell command" ergonomics, while still being safe via forced-command + a narrow command surface

---

## Requirements (MVP)

* **R1. Remote connectivity**: Clawdbot runs on a VPS but can securely execute file operations on a local macOS laptop while it is online.
* **R2. No Obsidian dependency**: Operate on plain Markdown (`.md`) files only; no Obsidian app/plugins required.
* **R3. Vault sandboxing**: All reads/writes must be restricted to a configured vault root directory (prevent path traversal).
* **R4. Resolve note**: Ability to target a note by **path** or by **title** (filename match).
* **R5. Efficient reading for long notes**: Provide “read primitives” that avoid reading whole files:
  * `info` (size/lines/hash)
  * `outline` (headings only)
  * `search` (with line numbers, optional context)
  * `read_range` (specific line range)
  * optional `head`/`tail`
* **R6. Prompt-based editing**: Ability to “edit according to a prompt” without rewriting everything by default.
* **R7. Safe writes**: Backups + concurrency checks + atomic-ish apply (fail cleanly, no silent partial edits).
* **R8. Predictable tool contract**: Skill exposes a small set of commands with clear inputs/outputs (JSON-friendly).
* **R9. Minimal operational burden**: Setup should be straightforward and stable for daily use.

---

## R1. Remote connectivity

### Implementation guide

**Reverse SSH tunnel with forced-command restriction**

* Mac initiates a persistent SSH connection to the VPS and opens a reverse port.
* VPS connects to `localhost:<MAC_TUNNEL_PORT>` to reach the Mac SSH server.
* All commands are routed through `vaultctl` via SSH forced-command.

**Setup on Mac:**
```bash
# Start reverse tunnel (run via launchd for persistence)
ssh -N -R <MAC_TUNNEL_PORT>:localhost:22 <VPS_USER>@<VPS_HOST>
```

**Setup on VPS:**
```bash
# Skill executes commands like:
ssh -p <MAC_TUNNEL_PORT> localhost vaultctl info "Projects/Plan.md"
```

### Notes

* Future: Cloudflare Tunnel can be added as an alternative without changing the `vaultctl` interface.

---

## R2. No Obsidian dependency

### Implementation guide

* Treat the vault as a normal folder of text files.
* Use standard Unix tools on macOS via SSH (`cat`, `sed`, `grep`, `stat`, `wc`, `shasum`, `cp`, `mv`).
* No `.obsidian/` parsing required in MVP.

---

## R3. Vault sandboxing

### Implementation guide

**Goal:** Prevent the agent from reading `/etc/passwd` because it "found a path."

* Configure `VAULT_ROOT` on the Mac side (e.g. `~/NotesVault`) via environment variable or config file.
* `vaultctl` resolves every candidate path to an absolute path and validates it is inside `VAULT_ROOT`.

**Sandboxing logic in vaultctl:**

```bash
resolve_and_validate() {
  local candidate="$1"
  local abs_candidate=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$candidate")
  local abs_vault=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$VAULT_ROOT")

  if [[ "$abs_candidate" != "$abs_vault" && "$abs_candidate" != "$abs_vault/"* ]]; then
    echo '{"error": "path outside vault"}' >&2
    exit 1
  fi
  echo "$abs_candidate"
}
```

If the check fails: `vaultctl` returns a hard error and exits non-zero.

---

## R4. Resolve note by path or title

### Implementation guide

`vaultctl resolve` supports two selector modes:

**A) Path (preferred)**

```bash
vaultctl resolve --path "Projects/Plan.md"
# Returns: {"resolved_path": "/Users/me/Vault/Projects/Plan.md"}
```

* Resolve: `VAULT_ROOT/Projects/Plan.md` (then sandbox-check)

**B) Title (filename match)**

```bash
vaultctl resolve --title "Project Plan"
# Returns: {"resolved_path": "/Users/me/Vault/Projects/Project Plan.md"}
# Or: {"error": "multiple matches", "candidates": [...]}
```

* Strategy (MVP):
  * Try exact filename: `"Project Plan.md"`
  * If not found, do a case-insensitive search by filename:
    * `find "$VAULT_ROOT" -type f -name "*.md" -iname "Project Plan.md" | head -n 2`
  * If 0 matches: `{"error": "not found"}`
  * If 1 match: use it
  * If >1 matches: return list for disambiguation

Return a canonical `resolved_path` for all downstream `vaultctl` calls.

---

## R5. Efficient reading for long notes

### Implementation guide

Expose these primitives as separate `vaultctl` subcommands so the agent naturally does:
**info → outline/search → read-range → (maybe expand range)**
instead of reading whole files.

### `vaultctl info <path>`

```bash
vaultctl info "/Users/me/Vault/Projects/Plan.md"
# Returns: {"lines": 1234, "bytes": 45678, "sha256": "abc123...", "mtime": 1706000000}
```

Internal implementation:
```bash
LINES=$(wc -l < "$FILE" | tr -d ' ')
BYTES=$(stat -f%z "$FILE")
SHA=$(shasum -a 256 "$FILE" | awk '{print $1}')
MTIME=$(stat -f%m "$FILE")
echo "{\"lines\":$LINES,\"bytes\":$BYTES,\"sha256\":\"$SHA\",\"mtime\":$MTIME}"
```

### `vaultctl outline <path> [--max-headings N]`

Return headings with line numbers (fast navigation):

```bash
vaultctl outline "/Users/me/Vault/Projects/Plan.md" --max-headings 200
# Returns: {"headings": [{"line": 1, "text": "# Title"}, {"line": 15, "text": "## Section"}...]}
```

Internal: `grep -nE '^#{1,6} ' "$FILE" | head -n $MAX`

### `vaultctl search <path> <pattern> [--max-hits N] [--context N]`

```bash
vaultctl search "/Users/me/Vault/Projects/Plan.md" "TODO" --max-hits 20 --context 2
# Returns: {"matches": [{"line": 42, "text": "- TODO: fix bug", "context_before": [...], "context_after": [...]}...]}
```

Internal: Prefer ripgrep if installed (`rg -n -m $MAX -C $CTX`); fallback to grep.

### `vaultctl read-range <path> <start_line> <end_line>`

```bash
vaultctl read-range "/Users/me/Vault/Projects/Plan.md" 100 150
# Returns: {"start": 100, "end": 150, "text": "..."}
```

Internal: `sed -n "${START},${END}p" "$FILE"`

### Optional: `vaultctl head` / `vaultctl tail`

```bash
vaultctl head "/Users/me/Vault/Projects/Plan.md" --lines 200
vaultctl tail "/Users/me/Vault/Projects/Plan.md" --lines 200
```

### Agent heuristic (recommended default behavior)

* If `lines <= 400`: read whole file via `read-range 1 <lines>`.
* If `lines > 400`: do `outline`, then `search`, then `read-range` around the best match, expanding as needed.

---

## R6. Prompt-based editing ("edit according to prompt")

### Implementation guide

Use a two-step strategy that edits *locally* and *minimally*:

1. **Locate the edit region**

* `vaultctl outline` to find the right section (by heading)
* and/or `vaultctl search` to find the exact area
* then `vaultctl read-range` to fetch just enough context (typically 120–200 lines)

2. **Apply a minimal patch**

* The model produces a **unified diff** against the exact slice context it saw (plus file path + base hash).
* The skill calls `vaultctl apply-patch` on the Mac.

```bash
vaultctl apply-patch "/Users/me/Vault/Projects/Plan.md" "abc123..." <<'EOF'
--- a/Projects/Plan.md
+++ b/Projects/Plan.md
@@ -42,3 +42,4 @@
 existing line
-old line
+new line
+added line
EOF
# Returns: {"status": "ok", "new_sha256": "def456..."}
```

Why patch-based:

* It avoids full-file rewrites.
* It fails cleanly if context does not match.

---

## R7. Safe writes (backup, concurrency, clean failure)

### Implementation guide

All safety checks are enforced inside `vaultctl apply-patch`:

**Concurrency check**

* Before applying any write, `vaultctl` re-checks the file hash:
  * If current hash != `base_sha256`, abort with:
    ```json
    {"error": "hash_mismatch", "expected": "abc123...", "actual": "xyz789..."}
    ```

**Backups**

* `vaultctl` always creates a timestamped backup before modifying:
```bash
cp "$FILE" "$FILE.bak.$(date +%Y%m%d-%H%M%S)"
```

**Apply patch**

Internal options (in order of preference):
* `patch -u "$FILE" < "$PATCHFILE"`
* `git apply` (if git is available)
* Tiny Python patch applier (future fallback if needed)

**Post-verify**

* `vaultctl` recomputes hash and returns it:
  ```json
  {"status": "ok", "new_sha256": "def456...", "backup": "Plan.md.bak.20240126-143022"}
  ```

**Failure behavior**

* If apply fails: do not modify the file (or restore from backup immediately).
* Return the patch error so the agent can adjust context and retry:
  ```json
  {"error": "patch_failed", "details": "Hunk #1 FAILED at 42."}
  ```

---

## R8. Predictable tool contract (vaultctl CLI)

### Implementation guide

`vaultctl` exposes subcommands with strict input/output (JSON on stdout):

**Core commands:**

```bash
vaultctl resolve --path <path> | --title <title>
vaultctl info <resolved_path>
vaultctl outline <resolved_path> [--max-headings N]
vaultctl search <resolved_path> <pattern> [--max-hits N] [--context N]
vaultctl read-range <resolved_path> <start_line> <end_line>
vaultctl apply-patch <resolved_path> <base_sha256> < <patch_file>
```

**Optional (nice-to-have):**

```bash
vaultctl edit-exact <resolved_path> <base_sha256> --old <text> --new <text> [--count N]
```
* Refuse if `old` appears 0 times or more than `--count` (default 1).

**Exit codes:**
* `0` = success (JSON result on stdout)
* `1` = user error (invalid args, path outside vault, hash mismatch)
* `2` = system error (file not found, patch failed)

---

## R9. Minimal operational burden (Setup + runtime)

### Implementation guide

**Configuration on VPS (Clawdbot):**

* `MAC_TUNNEL_PORT` - port where Mac is exposed via reverse tunnel

**Configuration on Mac:**

* `VAULT_ROOT` - path to vault directory (e.g., `~/NotesVault`)
* SSH enabled with VPS public key in `~/.ssh/authorized_keys`
* `vaultctl` installed (e.g., `/usr/local/bin/vaultctl`)

**`authorized_keys` entry on Mac:**
```
command="/usr/local/bin/vaultctl-wrapper",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA... vps-bot-key
```

Where `vaultctl-wrapper` extracts the command from `$SSH_ORIGINAL_COMMAND` and validates it starts with `vaultctl`.

**Operational expectations**

* Mac must be online and tunnel must be active.
* No sync required; edits are real-time on the Mac filesystem.

**Security defaults**

* SSH keys only (no passwords).
* Forced-command restriction prevents arbitrary command execution.
* `vaultctl` enforces vault sandboxing internally.

---

## Appendix: Suggested "edit note" agent loop (behavioral spec)

```
1. vaultctl resolve --path "..." | --title "..."
2. vaultctl info <resolved_path>
3. If lines > 400:
   a. vaultctl outline <resolved_path>
   b. vaultctl search <resolved_path> "<keywords>"
   c. vaultctl read-range <resolved_path> <start> <end>  # around best match
4. Generate a unified diff (minimal)
5. vaultctl apply-patch <resolved_path> <sha256> < patch
6. If hash mismatch or patch fails:
   a. re-run search/read-range with updated context
   b. regenerate diff
   c. retry once (MVP), then stop with error
```

---

## Appendix: Full SSH command examples

From VPS, all operations are invoked as:

```bash
# Resolve by path
ssh -p $MAC_TUNNEL_PORT localhost vaultctl resolve --path "Projects/Plan.md"

# Get file info
ssh -p $MAC_TUNNEL_PORT localhost vaultctl info "/Users/me/Vault/Projects/Plan.md"

# Read a range
ssh -p $MAC_TUNNEL_PORT localhost vaultctl read-range "/Users/me/Vault/Projects/Plan.md" 100 200

# Apply a patch (pipe via stdin)
ssh -p $MAC_TUNNEL_PORT localhost vaultctl apply-patch "/Users/me/Vault/Projects/Plan.md" "abc123..." <<'EOF'
--- a/Projects/Plan.md
+++ b/Projects/Plan.md
@@ -42,1 +42,2 @@
-old line
+new line
+added line
EOF
```
