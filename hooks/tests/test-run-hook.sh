#!/bin/bash
# Tests run-hook.js: exit code and stdin must reach Claude Code unchanged.
# Uses a copy of run-hook.js next to fake hooks, so no real hook is involved.
#
# Usage: ./test-run-hook.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp "$SCRIPT_DIR/../run-hook.js" "$TMP_DIR/"
printf '#!/bin/bash\nexit 2\n' > "$TMP_DIR/block.sh"
printf '#!/bin/bash\nexit 0\n' > "$TMP_DIR/allow.sh"
printf '#!/bin/bash\ncat\n' > "$TMP_DIR/echo-stdin.sh"

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

node "$TMP_DIR/run-hook.js" block < /dev/null; check "exit 2 is relayed" 2 $?
node "$TMP_DIR/run-hook.js" allow < /dev/null; check "exit 0 is relayed" 0 $?
node "$TMP_DIR/run-hook.js" missing < /dev/null; check "missing hook exits 0" 0 $?
node "$TMP_DIR/run-hook.js" < /dev/null; check "no hook name exits 0" 0 $?
out=$(echo '{"tool_name":"Bash"}' | node "$TMP_DIR/run-hook.js" echo-stdin)
check "stdin reaches the hook" '{"tool_name":"Bash"}' "$out"

exit $FAILED
