#!/bin/bash
# Tests the scope check on Bash file commands (cp, mv, sed -i): the target
# must come from tool_input.command, not from the raw JSON (whose last word
# belongs to "description").
#
# Usage: ./test-scope-bash.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export DEVTEAM_DIR="$TMP_DIR/.devteam"
mkdir -p "$DEVTEAM_DIR"
echo "src/" > "$DEVTEAM_DIR/task-scope.txt"
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

# Sends a PreToolUse event for <tool> with <field>=<value>; prints the exit code
event() {
    node -e 'const [t, k, v] = process.argv.slice(1);
             const input = { [k]: v };
             if (t === "Bash") input.description = "Copy file";
             console.log(JSON.stringify({ tool_name: t, tool_input: input }));' "$1" "$2" "$3" \
        | node "$HOOKS_DIR/run-hook.js" pre-tool-use-hook > /dev/null 2>&1
    echo $?
}

check "cp inside scope passes"      0 "$(event Bash command "cp src/a.php src/b.php")"
check "mv inside scope passes"      0 "$(event Bash command "mv src/a.php src/c.php")"
check "sed -i inside scope passes"  0 "$(event Bash command "sed -i 's/x/y/' src/f.php")"
check "Edit inside scope passes"    0 "$(event Edit file_path "src/a.php")"
check "Write inside scope passes"   0 "$(event Write file_path "src/new.php")"

check "cp outside scope blocks"     2 "$(event Bash command "cp src/a.php /etc/b.php")"
check "mv outside scope blocks"     2 "$(event Bash command "mv /etc/passwd /tmp/")"
check "sed -i outside scope blocks" 2 "$(event Bash command "sed -i 's/x/y/' /etc/hosts")"
check "Edit outside scope blocks"   2 "$(event Edit file_path "/etc/hosts")"
check "Write outside scope blocks"  2 "$(event Write file_path "config/app.php")"

exit $FAILED
