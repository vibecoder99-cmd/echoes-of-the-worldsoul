#!/bin/bash
# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
#
# Thin entry point. Contains no installer logic of its own -- it only
# locates python3 and this repo's installer/cli.py and hands off argv
# unchanged. Works from any working directory; does not assume any
# personal user/distro/client path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found on PATH. The Echoes installer requires Python 3." >&2
  exit 1
fi

exec python3 "$REPO_ROOT/installer/cli.py" "$@"
