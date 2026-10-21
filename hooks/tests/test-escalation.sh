#!/bin/bash
# Tests that repeated quality gate failures escalate the model without
# crashing post-tool-use-hook.sh, and that trigger_escalation(reason) alone
# (persistence-hook) still works under set -u.
#
# Usage: ./test-escalation.sh

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

# Opens a session (with <model> as current model if given), runs a failing
# phpunit twice; prints "exit=<last code> model=<model> escalations=<count>"
two_failures() {
    bash -c '
        export DEVTEAM_DIR="$1/.devteam"
        source "$2/lib/hook-common.sh"; set +e; trap - ERR
        init_hook test; start_session test test > /dev/null
        [[ -n "$3" ]] && set_current_model "$3"
        for i in 1 2; do
            CLAUDE_TOOL_NAME=Bash CLAUDE_TOOL_INPUT="{\"command\":\"phpunit\"}" CLAUDE_TOOL_RESULT="FAILURES!" \
                bash "$2/post-tool-use-hook.sh" < /dev/null > /dev/null 2>&1
            code=$?
        done
        echo "exit=$code model=$(get_current_model) escalations=$(sql_exec "SELECT COUNT(*) FROM escalations;")"
    ' _ "$TMP_DIR/$RANDOM" "$HOOKS_DIR" "$1" 2> /dev/null
}

check "haiku escalates to sonnet" "exit=0 model=sonnet escalations=1" "$(two_failures haiku)"
check "no current model: no escalation, no crash" "exit=0 model= escalations=0" "$(two_failures "")"

out=$(bash -c '
    export DEVTEAM_DIR="$1/.devteam"
    source "$2/lib/hook-common.sh"; set -u
    init_hook test
    trigger_escalation "3 abandonment attempts"
    echo "returned=$?"
' _ "$TMP_DIR/$RANDOM" "$HOOKS_DIR" 2> /dev/null)
check "trigger_escalation with reason only returns" "returned=0" "$out"

# Sequential ladder: the default threshold is 2 failures. Each escalation
# must reset the counter, so the next rung takes 2 more failures.
# Prints "<model>/<failures>" after each failure, space-separated.
ladder() {
    bash -c '
        export DEVTEAM_DIR="$1/.devteam"
        source "$2/lib/hook-common.sh"; set +e; trap - ERR
        init_hook test; start_session test test > /dev/null
        [[ -n "$3" ]] && set_current_model "$3"
        out=""
        for i in $(seq "$4"); do
            CLAUDE_TOOL_NAME=Bash CLAUDE_TOOL_INPUT="{\"command\":\"phpunit\"}" CLAUDE_TOOL_RESULT="FAILURES!" \
                bash "$2/post-tool-use-hook.sh" < /dev/null > /dev/null 2>&1
            out+="$(get_current_model)/$(get_consecutive_failures) "
        done
        echo "${out% }"
    ' _ "$TMP_DIR/$RANDOM" "$HOOKS_DIR" "$1" "$2" 2> /dev/null
}

check "ladder resets the counter at each rung" \
    "haiku/1 sonnet/0 sonnet/1 opus/0 opus/1 bug_council/0" "$(ladder haiku 6)"
check "no escalation possible: counter keeps growing" \
    "/1 /2 /3" "$(ladder "" 3)"
check "past bug_council: counter keeps growing" \
    "bug_council/1 bug_council/2 bug_council/3" "$(ladder bug_council 3)"

exit $FAILED
