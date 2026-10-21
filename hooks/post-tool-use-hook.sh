#!/bin/bash
# DevTeam Post-Tool-Use Hook
# Runs AFTER each tool call to log, detect patterns, and guide next steps
#
# Exit codes:
#   0 = Continue normally
#   (Post hooks typically don't block, just observe and inject guidance)
#
# Input: the JSON event Claude Code sends on stdin (tool_name,
# tool_input.command, tool_response). Only Bash output is analyzed.
# Fallback when stdin is empty (legacy test suite):
#   CLAUDE_TOOL_NAME - Name of the tool that was called
#   CLAUDE_TOOL_INPUT - JSON input for the tool (command)
#   CLAUDE_TOOL_RESULT - Result/output from the tool

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library with fallback paths (H6)
if [[ -f "$SCRIPT_DIR/lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/lib/hook-common.sh"
elif [[ -f "$SCRIPT_DIR/../lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/../lib/hook-common.sh"
else
    echo "[post-tool-use] Warning: hook-common.sh not found" >&2
    exit 0
fi

init_hook "post-tool-use"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Prints a field of the JSON event read on stdin: tool_name, command, or
# result (Bash stdout + stderr). node is always present: hooks run through run-hook.js
event_field() {
    node -e '
        let s = "";
        process.stdin.on("data", d => s += d).on("end", () => {
            let j = {};
            try { j = JSON.parse(s); } catch (e) {}
            const r = j.tool_response || {};
            const fields = {
                tool_name: j.tool_name,
                command: (j.tool_input || {}).command,
                result: typeof r === "string" ? r : [r.stdout, r.stderr].filter(Boolean).join("\n"),
            };
            process.stdout.write(fields[process.argv[1]] || "");
        });' "$1"
}

HOOK_INPUT=""
[[ -t 0 ]] || HOOK_INPUT=$(cat)

if [[ -n "$HOOK_INPUT" ]]; then
    TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | event_field tool_name)
    TOOL_COMMAND=$(printf '%s' "$HOOK_INPUT" | event_field command)
    TOOL_RESULT=""
    # Other tools' responses hold file contents, whose "Error" words would count as failures
    if [[ "$TOOL_NAME" == "Bash" ]]; then
        TOOL_RESULT=$(printf '%s' "$HOOK_INPUT" | event_field result)
    fi
else
    TOOL_NAME="${CLAUDE_TOOL_NAME:-}"
    TOOL_COMMAND=$(printf '{"tool_input":%s}' "${CLAUDE_TOOL_INPUT:-null}" | event_field command)
    TOOL_RESULT="${CLAUDE_TOOL_RESULT:-}"
fi

# ============================================================================
# OUTCOME DETECTION PATTERNS
# ============================================================================

# Patterns indicating failure (case-sensitive; counts must be non-zero so
# "0 failures" in a passing run does not match)
FAILURE_PATTERNS=(
    "FAILURES!"
    "ERRORS!"
    "FAILED"
    "FAIL "
    "(Failures|Errors): [1-9]"
    "[1-9][0-9]* (failed|failing|failures?|errors?|problems?)"
    "Found [1-9][0-9]* errors?"
    "FOUND [1-9][0-9]* ERRORS?"
    "error TS[0-9]+"
    "Traceback"
    "Fatal error"
    "SyntaxError"
    "Build failed"
    "Test failed"
    "Compilation failed"
    "Permission denied"
    "No such file or directory"
    "command not found"
)

# Patterns indicating success
SUCCESS_PATTERNS=(
    "OK \\("
    "[0-9]+ passed"
    "All tests pass"
    "0 errors"
    "0 failures"
    "No errors"
    "no problems"
    "Build succeeded"
)

# ============================================================================
# OUTCOME DETECTION
# ============================================================================

detect_outcome() {
    local result="$1"

    # Check for failure patterns first (more specific, takes priority)
    for pattern in "${FAILURE_PATTERNS[@]}"; do
        if echo "$result" | grep -qE "$pattern"; then
            echo "failure"
            return
        fi
    done

    # Check for success patterns
    for pattern in "${SUCCESS_PATTERNS[@]}"; do
        if echo "$result" | grep -qE "$pattern"; then
            echo "success"
            return
        fi
    done

    echo "unknown"
}

# ============================================================================
# QUALITY GATE DETECTION
# ============================================================================

# Prints "<gate> <gate_type>" for a quality gate command, nothing otherwise
gate_for_command() {
    local command="$1"

    if echo "$command" | grep -qE "(pytest|jest|vitest|mocha|go test|npm (run )?test|yarn test|bun test|rspec|phpunit|pest|artisan test|cargo test)"; then
        echo "tests test"
    elif echo "$command" | grep -qE "(tsc|mypy|pyright|phpstan|psalm)"; then
        echo "typecheck type"
    elif echo "$command" | grep -qE "(eslint|ruff|golangci-lint|rubocop|phpcs|pint|flake8|pylint|biome|prettier)"; then
        echo "lint lint"
    elif echo "$command" | grep -qE "(bandit|npm audit|yarn audit|composer audit|gosec|brakeman|safety|snyk|trivy)"; then
        echo "security security"
    elif echo "$command" | grep -qE "(--cov|coverprofile|lcov|nyc|c8)"; then
        echo "coverage coverage"
    elif echo "$command" | grep -qE "(npm run build|vite build|webpack|esbuild|rollup|cargo build|go build)"; then
        echo "build build"
    fi
}

detect_quality_gate() {
    local gate="$1"
    local gate_type="$2"
    local result="$3"

    if [[ -n "$gate" ]]; then
        local outcome
        outcome=$(detect_outcome "$result")
        local passed="false"
        [[ "$outcome" == "success" ]] && passed="true"

        log_info "post-tool-use" "Quality gate detected: $gate ($outcome)"
        log_event_to_db "gate_result" "gate" "Gate $gate: $outcome" \
            "{\"gate\": \"$gate\", \"type\": \"$gate_type\", \"passed\": $passed}"

        # If gate failed, provide guidance
        if [[ "$passed" == "false" ]]; then
            local error_count
            error_count=$(echo "$result" | grep -ciE "(error|fail)" || echo "0")

            inject_system_message "gate-failed" "
QUALITY GATE FAILED: $gate

Detected approximately $error_count error(s).

Next steps:
1. Analyze the specific errors above
2. Fix the issues one at a time
3. Re-run the $gate gate to verify fixes
4. Continue until gate passes

Do not proceed to the next task until this gate passes.
"
        fi
    fi
}

# ============================================================================
# FAILURE TRACKING & ESCALATION
# ============================================================================

handle_failure() {
    local result="$1"

    # Increment failure counter
    increment_failures

    local failures
    failures=$(get_consecutive_failures)
    local current_model
    current_model=$(get_current_model)

    log_warn "post-tool-use" "Failure detected (consecutive: $failures)"

    # Extract and store error summary
    local errors_file="$DEVTEAM_DIR/last-errors.txt"
    echo "$result" | grep -iE "(error|fail|exception|assert)" | head -20 > "$errors_file" 2>/dev/null || true

    # Determine escalation threshold
    local threshold=2
    if [[ "$ECO_MODE" == "true" ]]; then
        threshold=4
    fi

    # Check if escalation needed
    if [[ "$failures" -ge "$threshold" ]]; then
        local next_model
        case "$current_model" in
            haiku) next_model="sonnet" ;;
            sonnet) next_model="opus" ;;
            opus) next_model="bug_council" ;;
            *) next_model="" ;;
        esac

        trigger_escalation "$failures consecutive failures" "$current_model" "$next_model"

        if [[ "$next_model" == "bug_council" ]]; then
            inject_system_message "bug-council" "
BUG COUNCIL ACTIVATION REQUIRED

$failures consecutive failures with $current_model model.

The Bug Council must be activated to diagnose this issue.

The 5-member diagnostic team:
1. Root Cause Analyst - Identifies fundamental causes
2. Code Archaeologist - Examines code history and context
3. Pattern Matcher - Finds similar issues and solutions
4. Systems Thinker - Analyzes component interactions
5. Adversarial Tester - Challenges assumptions

Use devteam_bug_council_analyze if MCP is available.
"
        elif [[ -n "$next_model" ]]; then
            inject_system_message "escalation" "
MODEL ESCALATED

Previous model: $current_model
New model: $next_model
Reason: $failures consecutive failures

The escalated model has enhanced reasoning capabilities.

Please:
1. Review the previous errors carefully
2. Consider alternative approaches
3. Try a different strategy than before
"
        fi
    fi
}

# ============================================================================
# SUCCESS HANDLING
# ============================================================================

handle_success() {
    local result="$1"

    # Reset failure counter on success
    reset_failures

    log_info "post-tool-use" "Success detected"

    # Check if this looks like complete task success
    if echo "$result" | grep -qiE "(All tests pass|0 failed|100% passed|all.*gates.*pass)"; then
        log_info "post-tool-use" "Potential task completion detected"

        inject_system_message "completion-check" "
Tests appear to be passing.

Before marking complete, verify:
1. All acceptance criteria are met
2. All quality gates pass (tests, types, lint, security)
3. No scope violations occurred
4. Code is properly committed

If everything passes, report completion with EXIT_SIGNAL: true
"
    fi
}

# ============================================================================
# ERROR PATTERN ANALYSIS
# ============================================================================

analyze_error_patterns() {
    local result="$1"

    # Detect common error patterns and provide specific guidance

    # Missing dependency
    if echo "$result" | grep -qiE "(ModuleNotFoundError|Cannot find module|package.*not found)"; then
        inject_system_message "missing-dep" "
MISSING DEPENDENCY DETECTED

A required package or module is not installed.

Actions:
1. Identify the missing package from the error
2. Install it using the appropriate package manager
3. Re-run the failed command
"
    fi

    # Type errors
    if echo "$result" | grep -qiE "(TypeError|type.*mismatch|expected.*got)"; then
        inject_system_message "type-error" "
TYPE ERROR DETECTED

There's a type mismatch in the code.

Actions:
1. Check the expected vs actual types
2. Verify function signatures and return types
3. Add type annotations if helpful
"
    fi

    # Permission errors
    if echo "$result" | grep -qiE "(Permission denied|EACCES|EPERM)"; then
        inject_system_message "permission-error" "
PERMISSION ERROR DETECTED

The operation was blocked due to insufficient permissions.

Actions:
1. Check file/directory permissions
2. Verify you have access to the resource
3. Do NOT use sudo/admin unless absolutely necessary and user-approved
"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Skip if no tool result
    if [[ -z "$TOOL_RESULT" ]]; then
        exit 0
    fi

    # Only quality gate commands are analyzed: word matching on arbitrary
    # output (git log, grep) counted false failures
    local gate gate_type
    read -r gate gate_type <<< "$(gate_for_command "$TOOL_COMMAND")"
    if [[ "$TOOL_NAME" != "Bash" ]] || [[ -z "$gate" ]]; then
        exit 0
    fi

    # Failure counters live on the session: without one there is nothing to track
    if [[ -z "$(get_current_session_id 2>/dev/null)" ]]; then
        exit 0
    fi

    log_debug "post-tool-use" "Processing result from: $TOOL_NAME"

    # Detect outcome
    local outcome
    outcome=$(detect_outcome "$TOOL_RESULT")

    # Log tool execution
    log_event_to_db "tool_executed" "general" "Tool: $TOOL_NAME, Outcome: $outcome" \
        "{\"tool\": \"$TOOL_NAME\", \"outcome\": \"$outcome\"}"

    # Handle based on outcome
    case "$outcome" in
        failure)
            handle_failure "$TOOL_RESULT"
            analyze_error_patterns "$TOOL_RESULT"
            ;;
        success)
            handle_success "$TOOL_RESULT"
            ;;
        unknown)
            log_debug "post-tool-use" "Outcome unknown, no action taken"
            ;;
    esac

    # Detect and log quality gate results
    detect_quality_gate "$gate" "$gate_type" "$TOOL_RESULT"

    # Notify MCP server
    mcp_notify "post_tool_use" "$(get_claude_context)"

    exit 0
}

main "$@"
