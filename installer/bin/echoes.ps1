# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
#
# Thin entry point for Windows-side discovery/orchestration. Contains no
# installer logic of its own -- it only locates a Python interpreter and
# this repo's installer/cli.py and hands off arguments unchanged. Does not
# assume any personal user/distro/client path; does not hardcode WSL
# distro names.

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
}
if (-not $python) {
    Write-Error "Python was not found on PATH. The Echoes installer requires Python 3.7 or newer."
    exit 1
}

$detectedVersion = & $python.Source -c "import sys; print('.'.join(map(str, sys.version_info[:3])))"
$supported = & $python.Source -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 7) else 1)"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Echoes installer requires Python 3.7 or newer. Detected: $detectedVersion. Install/update Python and rerun this command."
    exit 1
}

& $python.Source (Join-Path $RepoRoot "installer\cli.py") @args
exit $LASTEXITCODE
