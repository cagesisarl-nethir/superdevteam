# DevTeam Hooks Installer (PowerShell)
# Prepares the hook scripts and installs the git pre-commit hook.
# Claude Code hooks are wired by the plugin (hooks/hooks.json): this script
# no longer writes settings.json, whose merge replaced the user's own hooks.
#
# Usage: .\install.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Write-Host ""
Write-Host "================================================================" -ForegroundColor Blue
Write-Host "             DevTeam Hooks Installer" -ForegroundColor Blue
Write-Host "================================================================" -ForegroundColor Blue
Write-Host ""

# ============================================================================
# INSTALL GIT HOOKS
# ============================================================================

$gitDir = Join-Path $ProjectRoot ".git"
if (Test-Path $gitDir) {
    Write-Host "Installing git hooks..."

    $gitHooksDir = Join-Path $gitDir "hooks"
    if (-not (Test-Path $gitHooksDir)) {
        New-Item -ItemType Directory -Path $gitHooksDir -Force | Out-Null
    }

    # Pre-commit hook
    $preCommitPath = Join-Path $gitHooksDir "pre-commit"
    @"
#!/bin/bash
exec "$ScriptDir/scope-check.sh"
"@ | Set-Content $preCommitPath -Encoding UTF8

    Write-Host "ok Git pre-commit hook installed" -ForegroundColor Green
} else {
    Write-Host "! Not a git repository - skipping git hooks" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# CREATE .devteam DIRECTORY
# ============================================================================

Write-Host "Creating .devteam directory..."

$DevteamDir = Join-Path $ProjectRoot ".devteam"
if (-not (Test-Path $DevteamDir)) {
    New-Item -ItemType Directory -Path $DevteamDir -Force | Out-Null
}

# Initialize database if script exists
$dbInitScript = Join-Path $ProjectRoot "scripts" "db-init.ps1"
if (Test-Path $dbInitScript) {
    Write-Host "Initializing database..."
    try {
        & $dbInitScript 2>$null
        Write-Host "ok Database initialized" -ForegroundColor Green
    } catch {
        # Ignore errors
    }
}

# Create hooks-installed marker so db-init.ps1 can detect it
New-Item -ItemType File -Path (Join-Path $DevteamDir ".hooks-installed") -Force | Out-Null

Write-Host "ok .devteam directory ready" -ForegroundColor Green
Write-Host ""

# ============================================================================
# VERIFICATION
# ============================================================================

Write-Host "Verifying installation..."
Write-Host ""

function Test-HookFile {
    param(
        [string]$Path,
        [string]$Name
    )

    if (Test-Path $Path) {
        Write-Host "  ok $Name" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  X $Name (missing)" -ForegroundColor Red
        return $false
    }
}

$errors = 0

if (-not (Test-HookFile (Join-Path $ScriptDir "lib\hook-common.ps1") "hook-common.ps1 (shared library)")) { $errors++ }
if (-not (Test-HookFile (Join-Path $ScriptDir "pre-tool-use-hook.ps1") "pre-tool-use-hook.ps1")) { $errors++ }
if (-not (Test-HookFile (Join-Path $ScriptDir "post-tool-use-hook.ps1") "post-tool-use-hook.ps1")) { $errors++ }
if (-not (Test-HookFile (Join-Path $ScriptDir "stop-hook.ps1") "stop-hook.ps1")) { $errors++ }
if (-not (Test-HookFile (Join-Path $ScriptDir "persistence-hook.ps1") "persistence-hook.ps1")) { $errors++ }
if (-not (Test-HookFile (Join-Path $ScriptDir "scope-check.ps1") "scope-check.ps1")) { $errors++ }
if (-not (Test-HookFile (Join-Path $ScriptDir "session-start.ps1") "session-start.ps1")) { $errors++ }
if (-not (Test-HookFile (Join-Path $ScriptDir "session-end.ps1") "session-end.ps1")) { $errors++ }
if (-not (Test-HookFile (Join-Path $ScriptDir "pre-compact.ps1") "pre-compact.ps1")) { $errors++ }

Write-Host ""

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host "================================================================" -ForegroundColor Blue
if ($errors -eq 0) {
    Write-Host "             Installation Complete" -ForegroundColor Green
} else {
    Write-Host "             Installation Complete (with warnings)" -ForegroundColor Yellow
}
Write-Host "================================================================" -ForegroundColor Blue
Write-Host ""
Write-Host "Hook scripts ready (wired in Claude Code by the plugin's hooks/hooks.json):"
Write-Host "  ok pre-tool-use-hook   - Scope validation, dangerous command blocking" -ForegroundColor Green
Write-Host "  ok post-tool-use-hook  - Failure tracking, escalation detection" -ForegroundColor Green
Write-Host "  ok stop-hook           - Exit control, checkpoint save" -ForegroundColor Green
Write-Host "  ok scope-check         - Git pre-commit scope validation" -ForegroundColor Green
Write-Host "  ok session-start       - Session initialization, context loading" -ForegroundColor Green
Write-Host "  ok session-end         - Session cleanup, memory persistence" -ForegroundColor Green
Write-Host "  ok pre-compact         - State preservation before compaction" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Install the DevTeam plugin to enable the Claude Code hooks (see README.md, Installation)"
Write-Host "  2. See '.\hooks\README.md' for configuration options"
Write-Host ""

if ($errors -gt 0) {
    Write-Host "Warning: $errors hook(s) may not be properly installed." -ForegroundColor Yellow
    Write-Host ""
}
