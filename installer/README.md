# Echoes of the Worldsoul Installer

Python core (`installer/core/`, `installer/cli.py`) with thin Bash
(`installer/bin/echoes.sh`) and PowerShell (`installer/bin/echoes.ps1`)
entry points, per the frozen E2J13 installer-technology decision. Neither
wrapper contains installer logic of its own -- both only locate a Python
interpreter and hand off arguments unchanged to `installer/cli.py`.

## Status

| Command | Status |
|---|---|
| `install` | Implemented and sandbox-tested (fresh install, repeat install) |
| `verify` | Implemented and sandbox-tested |
| `client-package` | Implemented and tested |
| `upgrade` | **Not yet implemented** -- raises `NotImplementedError` with a design note |
| `repair` | **Not yet implemented** -- raises `NotImplementedError` with a design note |
| `uninstall` | **Not yet implemented** -- raises `NotImplementedError` with a design note |

See each stub module's docstring (`installer/core/upgrade.py`,
`repair.py`, `uninstall.py`) for what's already designed vs. what's still
open.

## Usage

```
# Discover what's at a path -- read-only, safe to run anytime
python installer/cli.py discover --azerothcore-root /path/to/azerothcore --client-root /path/to/wow-client

# Install Echoes Core (Lua + mod-echoes-stats + SQL) only
python installer/cli.py install \
    --azerothcore-root /path/to/azerothcore \
    --mysql-user root --mysql-password '...' \
    --characters-database acore_characters --world-database acore_world

# ...plus Client Companion + Patch-4.MPQ (auto-extracts vanilla Item.dbc
# from the client's own stock archives; falls back to --vanilla-dbc-path
# if that fails)
python installer/cli.py install \
    --azerothcore-root /path/to/azerothcore \
    --mysql-user root --mysql-password '...' \
    --client-root /path/to/wow-client

# ...plus optional Playerbots integration (module is copied and left
# DISABLED; the installer never auto-enables it)
python installer/cli.py install \
    --azerothcore-root /path/to/azerothcore \
    --mysql-user root --mysql-password '...' \
    --with-playerbots

# Read-only verification
python installer/cli.py verify --azerothcore-root /path/to/azerothcore \
    --characters-database acore_characters --mysql-user root --mysql-password '...'

# Produce a distributable Client Companion bundle
python installer/cli.py client-package --output-dir ./release --vanilla-dbc-path ./my_Item.dbc
```

On Windows, use `installer\bin\echoes.ps1` in place of `python installer/cli.py`
(same arguments). On Linux/WSL, `installer/bin/echoes.sh`.

## Component model

- **Core required**: Echoes Lua (`lua_scripts/`), `mod-echoes-stats`,
  the SQL package. `mod-ale` is checked as an external prerequisite
  (never installed by this tool) -- install fails with clear remediation
  if it's missing.
- **Client recommended**: Client Companion AddOn + Patch-4.MPQ, only
  attempted if `--client-root` is supplied.
- **Playerbots optional**: `mod-echoes-playerbots`, only copied if
  `--with-playerbots` is passed AND `mod-playerbots` is detected at the
  target. Always left with `EchoesPlayerbots.Enable = 0` -- this
  installer never auto-enables Playerbots integration; that's an
  explicit, separate operator decision once compatibility is confirmed.

## Manifest

`<azerothcore-root>/echoes-install-manifest.json` -- see
`installer/core/manifest.py` for the schema. Records installed
components (with file hashes), applied SQL state, Playerbots-integration
state, config ownership, and every backup this installer has made. This
is what `verify`/`repair`/`upgrade`/`uninstall` read from -- none of them
re-derive ownership by guessing from paths or filenames.

## Patch-4.MPQ conflict policy

See `installer/core/mpq_conflict.py`'s module docstring: no E2J13 design
document explicitly defines this case, so the policy implemented here
(never silently overwrite a `patch-4.MPQ` that isn't recorded as
Echoes' own output; require `--force-mpq-overwrite`) is a direct,
conservative application of E2J13's general "no conflicting files that
aren't already Echoes-owned" principle, flagged for explicit confirmation
rather than treated as pre-approved.

## Testing

`installer/tests/test_installer_sandbox.py` -- plain-assertion suite (no
external test framework), matching this repository's existing style
(`dbc_patch/test_mpq_writer.py`). Discovery/config/conflict-policy tests
run with no external dependencies. The full install/verify test requires
a disposable MySQL instance, supplied via `ECHOES_TEST_MYSQL_HOST` (and
`_PORT`/`_USER`/`_PASSWORD`) -- it is skipped, not faked, when absent.
Never targets a real/live database or a real AzerothCore checkout.
