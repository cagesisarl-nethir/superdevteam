#!/bin/bash
# Tests that stop-hook.sh reads Claude's last message from the JSON event
# Claude Code sends on stdin (last_assistant_message).
#
# Usage: ./test-stop-hook-stdin.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

unset STOP_HOOK_MESSAGE CLAUDE_OUTPUT

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

# Runs the hook in autonomous mode in a fresh DEVTEAM_DIR; prints its exit code
run_hook() {
    export DEVTEAM_DIR="$TMP_DIR/$RANDOM/.devteam"
    mkdir -p "$DEVTEAM_DIR"
    touch "$DEVTEAM_DIR/autonomous-mode"
    node "$HOOKS_DIR/run-hook.js" stop-hook > /dev/null 2>&1
    echo $?
}

out=$(echo '{"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Done. EXIT_SIGNAL: true"}' | run_hook)
check "exit signal in last_assistant_message allows exit" 0 "$out"

out=$(echo '{"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"I am done for now"}' | run_hook)
check "no exit signal blocks exit" 2 "$out"

out=$(STOP_HOOK_MESSAGE="EXIT_SIGNAL: true" run_hook < /dev/null)
check "legacy env var still works" 0 "$out"

exit $FAILED
