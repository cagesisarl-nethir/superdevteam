#!/bin/bash
# Tests post-tool-use-hook.sh failure detection: only quality gate commands
# count, word matches in unrelated output do not, and no session means no-op.
#
# Usage: ./test-post-tool-use-detection.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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

# Runs the hook on <command> <output> in a fresh DEVTEAM_DIR with an open
# session; prints "exit=<code> failures=<count>"
run_hook() {
    bash -c '
        export DEVTEAM_DIR="$1/.devteam"
        source "$2/lib/hook-common.sh"; set +e; trap - ERR
        init_hook test; start_session test test > /dev/null
        CLAUDE_TOOL_NAME=Bash CLAUDE_TOOL_INPUT="{\"command\":\"$3\"}" CLAUDE_TOOL_RESULT="$4" \
            bash "$2/post-tool-use-hook.sh" < /dev/null > /dev/null 2>&1
        echo "exit=$? failures=$(get_consecutive_failures)"
    ' _ "$TMP_DIR/$RANDOM" "$HOOKS_DIR" "$1" "$2" 2> /dev/null
}

check "phpunit OK is a success" "exit=0 failures=0" \
    "$(run_hook "vendor/bin/phpunit" "OK (12 tests, 30 assertions)")"
check "'0 failures' is not a failure" "exit=0 failures=0" \
    "$(run_hook "npm test" "Tests: 12 passed, 0 failures")"
check "non-gate command is ignored" "exit=0 failures=0" \
    "$(run_hook "git log --oneline" "fix error handling in invoice")"
check "phpunit FAILURES! is a failure" "exit=0 failures=1" \
    "$(run_hook "php artisan test" $'FAILURES!\nTests: 3, Assertions: 5, Failures: 1.')"

CLAUDE_TOOL_NAME=Bash CLAUDE_TOOL_INPUT='{"command":"phpunit"}' CLAUDE_TOOL_RESULT="FAILURES!" \
    DEVTEAM_DIR="$TMP_DIR/no-session" bash "$HOOKS_DIR/post-tool-use-hook.sh" < /dev/null > /dev/null 2>&1
check "no session is a no-op" 0 $?

exit $FAILED
