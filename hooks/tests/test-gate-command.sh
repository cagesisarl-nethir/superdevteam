#!/bin/bash
# Tests gate_for_command: the gate comes from the command's first
# significant word (after VAR=value prefixes and cd), not a substring.
#
# Usage: ./test-gate-command.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")"

# Load only the function, not the hook's main
source <(sed -n '/^gate_for_command()/,/^}/p' "$HOOKS_DIR/post-tool-use-hook.sh")

FAILED=0

check() {
    local cmd="$1" expected="$2"
    local actual
    actual=$(gate_for_command "$cmd")
    actual="${actual%% *}"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS: '$cmd' -> '${expected:-none}'"
    else
        echo "  FAIL: '$cmd' (expected '${expected:-none}', got '${actual:-none}')"
        FAILED=1
    fi
}

check "phpunit"                                tests
check "vendor/bin/phpunit --filter Foo"        tests
check "npm test"                               tests
check "npx jest src"                           tests
check "c8 npm test"                            coverage
check "php artisan test"                       tests
check "cd app && vendor/bin/phpunit"           tests
check "APP_ENV=testing php artisan test"       tests

check "git show 3c8a1f2"                       ""
check "grep -rn phpunit ."                     ""
check "cat README.md"                          ""
check 'echo "phpunit"'                         ""
check "git log --grep=jest"                    ""

exit $FAILED
