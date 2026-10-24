#!/bin/bash
# Tests the escalation threshold of post-tool-use-hook.ps1 under pwsh:
# 2 consecutive failures escalate, 4 in eco mode. Skipped without pwsh.
#
# Usage: ./test-ps1-eco-mode.sh

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

# Second consecutive failure with sonnet, eco mode $1; prints "escalated" or "none"
second_failure() {
    export DEVTEAM_DIR="$TMP_DIR/$RANDOM/.devteam"
    mkdir -p "$DEVTEAM_DIR"
    sqlite3 "$DEVTEAM_DIR/devteam.db" < "$HOOKS_DIR/../scripts/schema.sql"
    sqlite3 "$DEVTEAM_DIR/devteam.db" "INSERT INTO sessions (id, command, command_type, status, current_model, consecutive_failures)
        VALUES ('s1', 'test', 'feature', 'running', 'sonnet', 1);"
    DEVTEAM_ECO_MODE="$1" CLAUDE_TOOL_NAME=Bash CLAUDE_TOOL_INPUT='{"command":"phpunit"}' CLAUDE_TOOL_RESULT="Tests: 1 FAILED" \
        "$PWSH" -NoProfile -File "$HOOKS_DIR/post-tool-use-hook.ps1" < /dev/null 2>&1 > /dev/null \
        | grep -q "MODEL ESCALATED" && echo escalated || echo none
}

check "eco mode off escalates at 2 failures" escalated "$(second_failure false)"
check "eco mode on waits for 4 failures" none "$(second_failure true)"

exit $FAILED
