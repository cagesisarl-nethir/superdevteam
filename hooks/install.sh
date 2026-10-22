#!/bin/bash
# DevTeam Hooks Installer
# Prepares the hook scripts and installs the git pre-commit hook.
# Claude Code hooks are wired by the plugin (hooks/hooks.json): this script
# no longer writes settings.json, whose merge replaced the user's own hooks.
#
# Usage: ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}             DevTeam Hooks Installer${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# ============================================================================
# MAKE HOOKS EXECUTABLE
# ============================================================================

echo "Making hooks executable..."

chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR"/lib/*.sh 2>/dev/null || true

echo -e "${GREEN}ok${NC} Hooks are executable"
echo ""

# ============================================================================
# INSTALL GIT HOOKS
# ============================================================================

if [[ -d "$PROJECT_ROOT/.git" ]]; then
    echo "Installing git hooks..."

    GIT_HOOKS_DIR="$PROJECT_ROOT/.git/hooks"
    mkdir -p "$GIT_HOOKS_DIR"

    # Pre-commit hook for scope checking
    cat > "$GIT_HOOKS_DIR/pre-commit" << EOF
#!/bin/bash
# DevTeam scope check hook
exec "$SCRIPT_DIR/scope-check.sh"
EOF
    chmod +x "$GIT_HOOKS_DIR/pre-commit"

    echo -e "${GREEN}ok${NC} Git pre-commit hook installed"
else
    echo -e "${YELLOW}!${NC} Not a git repository - skipping git hooks"
fi
echo ""

# ============================================================================
# CREATE .devteam DIRECTORY
# ============================================================================

echo "Creating .devteam directory..."

DEVTEAM_DIR="$PROJECT_ROOT/.devteam"
mkdir -p "$DEVTEAM_DIR"

# Initialize database if script exists
if [[ -x "$PROJECT_ROOT/scripts/db-init.sh" ]]; then
    echo "Initializing database..."
    "$PROJECT_ROOT/scripts/db-init.sh" 2>/dev/null || true
    echo -e "${GREEN}ok${NC} Database initialized"
fi

# Create hooks-installed marker so db-init.sh can detect it
touch "$DEVTEAM_DIR/.hooks-installed"

echo -e "${GREEN}ok${NC} .devteam directory ready"
echo ""

# ============================================================================
# VERIFICATION
# ============================================================================

echo "Verifying installation..."
echo ""

verify_file() {
    local file="$1"
    local name="$2"

    if [[ -f "$file" ]] && [[ -x "$file" ]]; then
        echo -e "  ${GREEN}ok${NC} $name"
        return 0
    else
        echo -e "  ${RED}X${NC} $name (missing or not executable)"
        return 1
    fi
}

ERRORS=0

verify_file "$SCRIPT_DIR/lib/hook-common.sh" "hook-common.sh (shared library)" || ERRORS=$((ERRORS + 1))
verify_file "$SCRIPT_DIR/pre-tool-use-hook.sh" "pre-tool-use-hook.sh" || ERRORS=$((ERRORS + 1))
verify_file "$SCRIPT_DIR/post-tool-use-hook.sh" "post-tool-use-hook.sh" || ERRORS=$((ERRORS + 1))
verify_file "$SCRIPT_DIR/stop-hook.sh" "stop-hook.sh" || ERRORS=$((ERRORS + 1))
verify_file "$SCRIPT_DIR/persistence-hook.sh" "persistence-hook.sh" || ERRORS=$((ERRORS + 1))
verify_file "$SCRIPT_DIR/scope-check.sh" "scope-check.sh" || ERRORS=$((ERRORS + 1))
verify_file "$SCRIPT_DIR/session-start.sh" "session-start.sh" || ERRORS=$((ERRORS + 1))
verify_file "$SCRIPT_DIR/session-end.sh" "session-end.sh" || ERRORS=$((ERRORS + 1))
verify_file "$SCRIPT_DIR/pre-compact.sh" "pre-compact.sh" || ERRORS=$((ERRORS + 1))

echo ""

# ============================================================================
# SUMMARY
# ============================================================================

echo -e "${BLUE}================================================================${NC}"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}             Installation Complete${NC}"
else
    echo -e "${YELLOW}             Installation Complete (with warnings)${NC}"
fi
echo -e "${BLUE}================================================================${NC}"
echo ""
echo "Hook scripts ready (wired in Claude Code by the plugin's hooks/hooks.json):"
echo -e "  ${GREEN}ok${NC} pre-tool-use-hook   - Scope validation, dangerous command blocking"
echo -e "  ${GREEN}ok${NC} post-tool-use-hook  - Failure tracking, escalation detection"
echo -e "  ${GREEN}ok${NC} stop-hook           - Exit control, checkpoint save"
echo -e "  ${GREEN}ok${NC} scope-check         - Git pre-commit scope validation"
echo -e "  ${GREEN}ok${NC} session-start       - Session initialization, context loading"
echo -e "  ${GREEN}ok${NC} session-end         - Session cleanup, memory persistence"
echo -e "  ${GREEN}ok${NC} pre-compact         - State preservation before compaction"
echo ""
echo "Next steps:"
echo "  1. Install the DevTeam plugin to enable the Claude Code hooks (see README.md, Installation)"
echo "  2. Run './hooks/tests/test-hooks.sh' to verify"
echo "  3. See './hooks/README.md' for configuration options"
echo ""

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${YELLOW}Warning: $ERRORS hook(s) may not be properly installed.${NC}"
    echo ""
fi
