#!/bin/bash
# Tests which PowerShell run-hook.js picks on Windows, simulated on Linux:
# process.platform is forced to win32 and execSync is replaced by a stub that
# prints the program it was asked to run (nothing is executed).
#
# Usage: ./test-run-hook-windows.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp "$SCRIPT_DIR/../run-hook.js" "$TMP_DIR/"
touch "$TMP_DIR/probe.ps1"
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/bin-pwsh"
touch "$TMP_DIR/bin-pwsh/pwsh.exe"

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

# Runs run-hook.js as on Windows with only the given dir in PATH
run_as_windows() {
    PATH="$TMP_DIR/$1" "$(command -v node)" -e "
        Object.defineProperty(process, 'platform', { value: 'win32' });
        require('child_process').execSync = cmd => console.log(cmd.split(' ')[0]);
        process.argv = [process.argv[0], '$TMP_DIR/run-hook.js', 'probe'];
        require('$TMP_DIR/run-hook.js');" < /dev/null
}

check "pwsh.exe on PATH runs pwsh" pwsh "$(run_as_windows bin-pwsh)"
check "no pwsh.exe falls back to powershell" powershell "$(run_as_windows bin)"
check "fallback says so on stderr" "[devteam] running under PowerShell 5.1" "$(run_as_windows bin 2>&1 > /dev/null)"
check "pwsh writes nothing on stderr" "" "$(run_as_windows bin-pwsh 2>&1 > /dev/null)"

exit $FAILED
