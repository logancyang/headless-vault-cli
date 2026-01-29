#!/bin/bash
#
# test_vaultctl.sh - Test suite for vaultctl CLI
#
# Usage:
#   ./tests/test_vaultctl.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VAULTCTL="$PROJECT_DIR/vaultctl/vaultctl"

# Test vault location
TEST_VAULT="/tmp/vaultctl-test-$$"
export VAULT_ROOT="$TEST_VAULT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_VAULT"
}
trap cleanup EXIT

# Test helpers
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    echo "  Expected: $2"
    echo "  Got: $3"
    FAILED=$((FAILED + 1))
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "exit code $expected" "exit code $actual"
    fi
}

assert_json_has() {
    local json="$1"
    local key="$2"
    local test_name="$3"
    if echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); assert '$key' in d" 2>/dev/null; then
        pass "$test_name"
    else
        fail "$test_name" "JSON with key '$key'" "$json"
    fi
}

assert_json_value() {
    local json="$1"
    local key="$2"
    local expected="$3"
    local test_name="$4"
    local actual
    actual=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)['$key'])" 2>/dev/null || echo "KEY_NOT_FOUND")
    if [[ "$actual" == "$expected" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "$key=$expected" "$key=$actual"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$test_name"
    else
        fail "$test_name" "contains '$needle'" "$haystack"
    fi
}

# =============================================================================
# Setup test vault
# =============================================================================

echo "=== vaultctl Test Suite ==="
echo "Test vault: $TEST_VAULT"
echo

mkdir -p "$TEST_VAULT/Projects" "$TEST_VAULT/Notes"
echo -e "# Test Project\n\nThis is a test.\n\n## Section 1\n\nContent here." > "$TEST_VAULT/Projects/Plan.md"
echo "# Quick Note" > "$TEST_VAULT/Notes/Quick.md"
echo "# Another Note" > "$TEST_VAULT/Notes/Another.md"

# =============================================================================
# Test: tree
# =============================================================================

echo "--- Testing: tree ---"

output=$("$VAULTCTL" tree)
assert_json_has "$output" "tree" "tree returns tree key"
assert_contains "$output" "Projects/Plan.md" "tree contains Projects/Plan.md"
assert_contains "$output" "Notes/Quick.md" "tree contains Notes/Quick.md"

output=$("$VAULTCTL" tree --depth 1)
assert_contains "$output" '"type": "dir"' "tree --depth 1 shows directories"

# =============================================================================
# Test: resolve
# =============================================================================

echo "--- Testing: resolve ---"

output=$("$VAULTCTL" resolve --path "Projects/Plan.md")
assert_json_has "$output" "resolved_path" "resolve --path returns resolved_path"
assert_contains "$output" "Projects/Plan.md" "resolve --path contains correct path"

output=$("$VAULTCTL" resolve --title "Quick")
assert_json_has "$output" "resolved_path" "resolve --title returns resolved_path"
assert_contains "$output" "Quick.md" "resolve --title finds Quick.md"

output=$("$VAULTCTL" resolve --title "Nonexistent" 2>&1 || true)
assert_contains "$output" "error" "resolve --title nonexistent returns error"

# =============================================================================
# Test: info
# =============================================================================

echo "--- Testing: info ---"

output=$("$VAULTCTL" info "Projects/Plan.md")
assert_json_has "$output" "lines" "info returns lines"
assert_json_has "$output" "bytes" "info returns bytes"
assert_json_has "$output" "sha256" "info returns sha256"
assert_json_has "$output" "mtime" "info returns mtime"

# =============================================================================
# Test: read
# =============================================================================

echo "--- Testing: read ---"

output=$("$VAULTCTL" read "Projects/Plan.md")
assert_json_has "$output" "content" "read returns content"
assert_contains "$output" "Test Project" "read contains file content"

# =============================================================================
# Test: create
# =============================================================================

echo "--- Testing: create ---"

output=$("$VAULTCTL" create "Notes/NewNote.md" $'# New Note\n\nCreated by test.')
assert_json_value "$output" "status" "ok" "create returns status ok"
assert_json_has "$output" "sha256" "create returns sha256"

# Verify file exists
[[ -f "$TEST_VAULT/Notes/NewNote.md" ]] && pass "create actually creates file" || fail "create actually creates file" "file exists" "file missing"

# Test create fails if file exists
output=$("$VAULTCTL" create "Notes/NewNote.md" "duplicate" 2>&1 || true)
assert_contains "$output" "error" "create fails if file exists"

# Test create with nested path
output=$("$VAULTCTL" create "Deep/Nested/Note.md" "# Deep")
assert_json_value "$output" "status" "ok" "create with nested path succeeds"
[[ -f "$TEST_VAULT/Deep/Nested/Note.md" ]] && pass "create creates parent directories" || fail "create creates parent directories" "file exists" "file missing"

# =============================================================================
# Test: append
# =============================================================================

echo "--- Testing: append ---"

output=$("$VAULTCTL" append "Notes/NewNote.md" $'\n\n## Appended\n\nNew content.')
assert_json_value "$output" "status" "ok" "append returns status ok"

# Verify content was appended
content=$(cat "$TEST_VAULT/Notes/NewNote.md")
assert_contains "$content" "Appended" "append actually appends content"

# =============================================================================
# Test: sandbox security
# =============================================================================

echo "--- Testing: sandbox security ---"

if "$VAULTCTL" read "../../../etc/passwd" >/dev/null 2>&1; then
    fail "sandbox blocks path traversal" "command to fail" "command succeeded"
else
    pass "sandbox blocks path traversal"
fi

output=$("$VAULTCTL" read "../../../etc/passwd" 2>&1 || true)
assert_contains "$output" "outside vault" "sandbox error mentions 'outside vault'"

if "$VAULTCTL" read "/etc/passwd" >/dev/null 2>&1; then
    fail "sandbox blocks absolute paths outside vault" "command to fail" "command succeeded"
else
    pass "sandbox blocks absolute paths outside vault"
fi

# =============================================================================
# Test: error handling
# =============================================================================

echo "--- Testing: error handling ---"

output=$("$VAULTCTL" read "Nonexistent.md" 2>&1 || true)
assert_contains "$output" "error" "read nonexistent returns error"

output=$("$VAULTCTL" info "Nonexistent.md" 2>&1 || true)
assert_contains "$output" "error" "info nonexistent returns error"

# =============================================================================
# Summary
# =============================================================================

echo
echo "=== Test Summary ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
