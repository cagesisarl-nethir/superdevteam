#!/bin/bash
# Tests that a blocking .ps1 hook writes its reason, and its logs, to stderr:
# on exit 2 Claude Code feeds stderr back to Claude. Skipped without pwsh.
#
# Usage: ./test-ps1-block-message.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! command -v pwsh > /dev/null; then
    echo "  SKIP: pwsh not installed"
    exit 0
fi

export DEVTEAM_DIR="$TMP_DIR/.devteam"

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

CLAUDE_TOOL_NAME=Bash CLAUDE_TOOL_INPUT='{"command":"rm -rf /"}' \
    pwsh -NoProfile -File "$HOOKS_DIR/pre-tool-use-hook.ps1" < /dev/null > "$TMP_DIR/out" 2> "$TMP_DIR/err"
check "dangerous command exits 2" 2 $?
check "stdout is empty" "" "$(cat "$TMP_DIR/out")"
grep -q '^\[devteam-danger-blocked\]' "$TMP_DIR/err"
check "reason is on stderr" 0 $?

touch "$DEVTEAM_DIR/autonomous-mode"
STOP_HOOK_MESSAGE="I am done for now" \
    pwsh -NoProfile -File "$HOOKS_DIR/stop-hook.ps1" < /dev/null > "$TMP_DIR/out" 2> "$TMP_DIR/err"
check "stop without signal exits 2" 2 $?
check "stop-hook stdout is empty" "" "$(cat "$TMP_DIR/out")"
grep -q '^\[devteam-exit-blocked\]' "$TMP_DIR/err"
check "stop-hook reason is on stderr" 0 $?

exit $FAILED
