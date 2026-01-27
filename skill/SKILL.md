# Note Connector

Read and edit your local Markdown notes from Clawdbot.

## Setup

This skill requires setup on **both** your VPS and your Mac:

1. **VPS**: Install via `clawdhub install note-connector`
2. **Mac**: Clone the repo and run `./install.sh ~/YourNotesFolder`

See the [full setup guide](https://github.com/anthropics/clawd-note-connector#quick-start).

## Configuration

Set these environment variables on the VPS (or in your Clawdbot config):

```bash
export VAULT_SSH_PORT=2222
export VAULT_SSH_HOST=localhost
```

## Tools

### vault_tree

List the vault directory structure.

**Parameters:**
- `depth` (optional): Maximum depth to traverse
- `all` (optional): Include all files, not just .md

**Example:**
```
vault_tree depth=2
```

---

### vault_resolve

Find a note by path or title.

**Parameters:**
- `path` (optional): Relative path to the note
- `title` (optional): Note title to search for

**Example:**
```
vault_resolve title="Meeting Notes"
vault_resolve path="Projects/Plan.md"
```

---

### vault_info

Get metadata about a note.

**Parameters:**
- `path` (required): Path to the note

**Returns:** lines, bytes, sha256 hash, modification time

**Example:**
```
vault_info path="Projects/Plan.md"
```

---

### vault_read

Read the contents of a note.

**Parameters:**
- `path` (required): Path to the note

**Example:**
```
vault_read path="Projects/Plan.md"
```

---

### vault_create

Create a new note.

**Parameters:**
- `path` (required): Path for the new note (must end in .md)
- `content` (required): Content of the note

**Example:**
```
vault_create path="Notes/NewIdea.md" content="# New Idea\n\nThis is my new idea."
```

---

### vault_append

Append content to an existing note.

**Parameters:**
- `path` (required): Path to the note
- `content` (required): Content to append

**Example:**
```
vault_append path="Notes/Log.md" content="\n\n## 2024-01-26\n\nNew entry here."
```

## Usage Tips

1. Use `vault_tree` first to see what's in the vault
2. Use `vault_resolve` to find notes by title if you don't know the exact path
3. Use `vault_info` to check file size before reading large files
4. When appending, include leading newlines to separate from existing content
