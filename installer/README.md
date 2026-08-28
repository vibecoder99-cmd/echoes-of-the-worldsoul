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

# ...plus Client Companion + patch-E.MPQ (auto-extracts vanilla Item.dbc
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
- **Client recommended**: Client Companion AddOn + patch-E.MPQ, only
  attempted if `--client-root` is supplied. patch-E.MPQ ("E" for
  Echoes) is this project's own reserved client-patch slot -- not the
  older patch-4.MPQ, which is a common first custom-patch slot other
  mods/servers also reach for. A prior Echoes-owned patch-4.MPQ (proven
  by payload fingerprint, not filename) is migrated forward
  automatically; an unrelated patch-4.MPQ is left untouched.
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

## patch-E.MPQ namespace and conflict policy

See `installer/core/mpq_conflict.py`'s module docstring for the full
detail: load-support evidence (this project's own pre-existing
`patch-Z.mpq` documentation plus converging community documentation of
WoW 3.3.5a's patch-loading algorithm -- **not independently confirmed via
a live client launch this session**), the DBC merge-conflict caveat this
rename does not solve, and the ownership policy:

- patch-E.MPQ absent -> install normally.
- patch-E.MPQ present and proven Echoes-owned (hash matches this
  installer's manifest) -> upgrade/repair normally, backup first.
- patch-E.MPQ present and NOT proven Echoes-owned -> **block and report**.
  There is no `--force` option in the ordinary install path -- Echoes
  does not fight over a slot it doesn't already own.

No E2J13 design document explicitly defines this exact case; the policy
above is a direct, conservative application of E2J13's general "no
conflicting files that aren't already Echoes-owned" principle, flagged
for explicit confirmation rather than treated as pre-approved.

A prior Echoes-owned `patch-4.MPQ` (positively identified by payload
fingerprint -- see `installer/core/legacy_migration.py`, never by
filename alone) is migrated to `patch-E.MPQ` automatically as part of
`install`: backed up, then removed only after the new `patch-E.MPQ` is
verified in place. An unrelated `patch-4.MPQ` is never touched.

## Testing

`installer/tests/test_installer_sandbox.py` -- plain-assertion suite (no
external test framework), matching this repository's existing style
(`dbc_patch/test_mpq_writer.py`). Discovery/config/conflict-policy tests
run with no external dependencies. The full install/verify test requires
a disposable MySQL instance, supplied via `ECHOES_TEST_MYSQL_HOST` (and
`_PORT`/`_USER`/`_PASSWORD`) -- it is skipped, not faked, when absent.
Never targets a real/live database or a real AzerothCore checkout.
