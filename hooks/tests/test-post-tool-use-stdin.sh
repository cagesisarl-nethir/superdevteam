#!/bin/bash
# Tests that post-tool-use-hook.sh reads the JSON event Claude Code sends on stdin.
# A detected failure writes $DEVTEAM_DIR/last-errors.txt, used here as the probe.
#
# Usage: ./test-post-tool-use-stdin.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

unset CLAUDE_TOOL_NAME CLAUDE_TOOL_RESULT

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

# Runs the hook in a fresh DEVTEAM_DIR with an open session (failure
# handling needs one); prints "failure" if it recorded one
run_hook() {
    export DEVTEAM_DIR="$TMP_DIR/$RANDOM/.devteam"
    bash -c 'source "$1/lib/hook-common.sh"; init_hook test; start_session test test' _ "$HOOKS_DIR" > /dev/null 2>&1
    node "$HOOKS_DIR/run-hook.js" post-tool-use-hook > /dev/null 2>&1
    [[ -f "$DEVTEAM_DIR/last-errors.txt" ]] && echo failure || echo none
}

out=$(echo '{"tool_name":"Bash","tool_input":{"command":"phpunit"},"tool_response":{"stdout":"","stderr":"Tests: 1 FAILED"}}' | run_hook)
check "failure in Bash stderr is detected" failure "$out"

out=$(echo '{"tool_name":"Bash","tool_input":{"command":"phpunit"},"tool_response":{"stdout":"OK (3 tests)","stderr":""}}' | run_hook)
check "success in Bash stdout records no failure" none "$out"

out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"a.php"},"tool_response":{"filePath":"a.php","newString":"throw new Error:"}}' | run_hook)
check "non-Bash tool response is ignored" none "$out"

out=$(CLAUDE_TOOL_NAME=Bash CLAUDE_TOOL_INPUT='{"command":"phpunit"}' CLAUDE_TOOL_RESULT="Tests: 1 FAILED" run_hook < /dev/null)
check "legacy env vars still work" failure "$out"

exit $FAILED
