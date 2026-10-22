#!/usr/bin/env node
// Cross-platform hook runner for DevTeam
// Detects OS and runs the appropriate .sh (Unix) or .ps1 (Windows) hook script.
// Relays the hook's exit code (2 = block); exits 0 only if the hook could not run.

'use strict';

const { execSync } = require('child_process');
const { existsSync } = require('fs');
const { delimiter, join, resolve } = require('path');

const hookName = process.argv[2];

if (!hookName) {
  process.exit(0);
}

const isWindows = process.platform === 'win32';
const shScript = resolve(__dirname, hookName + '.sh');
const ps1Script = resolve(__dirname, hookName + '.ps1');

// hook-common.ps1 needs PowerShell 7 (??): Windows PowerShell 5.1 is only a fallback
const powershell = (process.env.PATH || '').split(delimiter)
  .some(dir => existsSync(join(dir, 'pwsh.exe'))) ? 'pwsh' : 'powershell';

try {
  if (isWindows) {
    if (existsSync(ps1Script)) {
      execSync(
        powershell + ' -ExecutionPolicy Bypass -NoProfile -File "' + ps1Script + '"',
        { stdio: 'inherit', timeout: 30000 }
      );
    }
  } else {
    if (existsSync(shScript)) {
      execSync('bash "' + shScript + '"', { stdio: 'inherit', timeout: 30000 });
    }
  }
} catch (e) {
  // status is null on timeout and undefined on spawn failure: degrade gracefully
  process.exit(typeof e.status === 'number' ? e.status : 0);
}
