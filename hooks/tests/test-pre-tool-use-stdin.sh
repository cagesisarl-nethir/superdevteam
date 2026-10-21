#!/bin/bash
# Tests that pre-tool-use-hook.sh reads the JSON event Claude Code sends on stdin.
#
# Usage: ./test-pre-tool-use-stdin.sh

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

event() {
    printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$1" "$2"
}

event Bash '{"command":"rm -rf /","description":"x"}' | bash "$HOOKS_DIR/pre-tool-use-hook.sh" >/dev/null 2>&1
check "dangerous command on stdin is blocked" 2 $?

event Bash '{"command":"ls -la"}' | bash "$HOOKS_DIR/pre-tool-use-hook.sh" >/dev/null 2>&1
check "safe command on stdin is allowed" 0 $?

event Edit '{"file_path":"src/a.php","old_string":"a","new_string":"b"}' | bash "$HOOKS_DIR/pre-tool-use-hook.sh" >/dev/null 2>&1
check "edit without scope file is allowed" 0 $?

event Bash '{"command":"rm -rf /"}' | node "$HOOKS_DIR/run-hook.js" pre-tool-use-hook >/dev/null 2>&1
check "dangerous command via run-hook.js is blocked" 2 $?

CLAUDE_TOOL_NAME=Bash CLAUDE_TOOL_INPUT='{"command":"rm -rf /"}' bash "$HOOKS_DIR/pre-tool-use-hook.sh" < /dev/null >/dev/null 2>&1
check "legacy env vars still work" 2 $?

exit $FAILED
