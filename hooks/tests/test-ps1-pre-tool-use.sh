#!/bin/bash
# Tests pre-tool-use-hook.ps1 under pwsh: the tool input must reach its checks.
# Skipped when pwsh is not installed.
#
# Usage: ./test-ps1-pre-tool-use.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# DEVTEAM_TEST_PWSH picks the PowerShell to test (powershell = Windows PowerShell 5.1)
PWSH="${DEVTEAM_TEST_PWSH:-pwsh}"

if ! command -v "$PWSH" > /dev/null; then
    echo "  SKIP: $PWSH not installed"
    exit 0
fi

FAILED=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS: $name"
    else
        echo "  FAIL: $name (expected '$expected', got '$actual')"
        FAILED=1
    fi
}

# Runs the hook with the legacy env vars in a fresh DEVTEAM_DIR; prints its exit code
run_hook() {
    DEVTEAM_DIR="$TMP_DIR/$RANDOM/.devteam" CLAUDE_TOOL_NAME="$1" CLAUDE_TOOL_INPUT="$2" \
        "$PWSH" -NoProfile -File "$HOOKS_DIR/pre-tool-use-hook.ps1" < /dev/null > /dev/null 2>&1
    echo $?
}

check "dangerous command blocks" 2 "$(run_hook Bash '{"command":"rm -rf /"}')"
check "safe command allowed" 0 "$(run_hook Bash '{"command":"ls -la"}')"

exit $FAILED
