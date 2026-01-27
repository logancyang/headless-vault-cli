#!/bin/bash
#
# run_all.sh - Run all vaultctl tests
#
# Usage:
#   ./tests/run_all.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "========================================"
echo "       vaultctl Test Suite"
echo "========================================"
echo

FAILED=0

run_test() {
    local test_script="$1"
    local test_name="$(basename "$test_script" .sh)"

    echo -e "${YELLOW}Running: $test_name${NC}"
    echo "----------------------------------------"

    if "$test_script"; then
        echo -e "${GREEN}$test_name: ALL PASSED${NC}"
    else
        echo -e "${RED}$test_name: SOME FAILED${NC}"
        ((FAILED++))
    fi
    echo
}

# Run tests
run_test "$SCRIPT_DIR/test_vaultctl.sh"
run_test "$SCRIPT_DIR/test_wrapper.sh"

# Summary
echo "========================================"
echo "       Final Summary"
echo "========================================"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All test suites passed!${NC}"
    exit 0
else
    echo -e "${RED}$FAILED test suite(s) had failures${NC}"
    exit 1
fi
