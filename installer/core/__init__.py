# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
#
# Echoes of the Worldsoul installer -- Python core.
#
# Architecture (frozen per E2J13-INSTALLER-TECHNOLOGY-EVALUATION.md): all
# real logic lives here. installer/bin/echoes.sh and installer/bin/echoes.ps1
# are thin entry points that invoke this package's CLI (installer/cli.py) --
# neither wrapper duplicates any decision this package makes.
