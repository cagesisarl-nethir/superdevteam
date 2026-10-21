#!/bin/bash
# Tests that a blocking hook's reason goes to stderr, the only stream
# Claude Code feeds back to Claude on exit 2.
#
# Usage: ./test-block-message.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export DEVTEAM_DIR="$TMP_DIR/.devteam"
unset CLAUDE_TOOL_NAME CLAUDE_TOOL_INPUT

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

echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
    | node "$HOOKS_DIR/run-hook.js" pre-tool-use-hook > "$TMP_DIR/out" 2> "$TMP_DIR/err"
check "dangerous command exits 2" 2 $?
check "stdout is empty" "" "$(cat "$TMP_DIR/out")"
grep -q "DANGEROUS COMMAND BLOCKED" "$TMP_DIR/err"
check "reason is on stderr" 0 $?

exit $FAILED
