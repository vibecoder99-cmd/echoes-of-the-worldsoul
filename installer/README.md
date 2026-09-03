# Echoes of the Worldsoul Installer

Python core (`installer/core/`, `installer/cli.py`) with thin Bash
(`installer/bin/echoes.sh`) and PowerShell (`installer/bin/echoes.ps1`)
entry points, per the frozen E2J13 installer-technology decision. Neither
wrapper contains installer logic of its own -- both only locate a Python
interpreter and hand off arguments unchanged to `installer/cli.py`.

## Status

| Command | Status |
|---|---|
| `install` | Implemented and sandbox-tested (fresh install, repeat install, partial-install failure recovery) |
| `verify` | Implemented and sandbox-tested |
| `upgrade` | Implemented and sandbox-tested (thin wrapper over `install()`'s own backup-before-replace + idempotent-SQL behavior; tested against a representative pre-manifest legacy layout) |
| `repair` | Implemented and sandbox-tested (missing files restored automatically; hash-mismatched files reported only, unless `--restore-mismatched`) |
| `uninstall` | Implemented and sandbox-tested (manifest-scoped removal, database retention by default; `--purge` not implemented -- future scope) |
| `client-package` | Implemented and tested |
| `discover` | Implemented (read-only) |

A prior checkpoint's `upgrade`/`repair`/`uninstall` stubs (with design
notes on the open questions each one resolved) have been superseded by
the real implementations above.

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
# from the client's own stock archives via the optional mpyq package;
# many real retail clients use an MPQ "extended header" format mpyq
# doesn't fully support -- if extraction fails, extract Item.dbc yourself
# with any MPQ editor and pass --vanilla-dbc-path instead, see INSTALL.md)
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

## Split Docker/DML-style runtime layouts

A traditional bare-metal AzerothCore checkout keeps `modules/`,
`lua_scripts/`, and `etc/` all directly under one root -- `--azerothcore-root`
alone is correct there, and this remains the default with no other flags
needed.

A Docker-based deployment can split this: C++ `modules/` only matters at
image-build time and lives at the checkout root, while the actual live
`lua_scripts/` and `etc/modules/` are bind-mounted from a separate runtime
distribution root (an `env/dist/`-style directory) that has no `modules/`
of its own. No single `--azerothcore-root` represents both in that shape.
`echoes discover` flags this automatically:

```
python installer/cli.py discover --azerothcore-root /path/to/azerothcore
# Detected split DML-style runtime layout. Suggested:
#   --azerothcore-root /path/to/azerothcore
#   --lua-root /path/to/azerothcore/env/dist
#   --config-root /path/to/azerothcore/env/dist
```

Pass the suggested (or your own) explicit roots on `install`/`upgrade`:

```
python installer/cli.py install \
    --azerothcore-root /path/to/azerothcore \
    --lua-root /path/to/azerothcore/env/dist \
    --config-root /path/to/azerothcore/env/dist \
    --mysql-user root --mysql-password '...' \
    --characters-database acore_characters --world-database acore_world
```

`--lua-root`/`--config-root` default to `--azerothcore-root` when omitted,
so every existing single-root invocation is unaffected. The installer
never infers a split layout on its own and never silently picks a root --
`discover`'s suggestion is diagnostic only. `verify`/`repair`/`uninstall`
read the effective roots back out of the install manifest (which records
them), so they don't need these flags repeated; a manifest written before
this feature existed is still read correctly, defaulting both roots to
its recorded `azerothcore_root`.

On Windows, use `installer\bin\echoes.ps1` in place of `python installer/cli.py`
(same arguments). On Linux/WSL, `installer/bin/echoes.sh`.

## Component model

- **Core required**: Echoes Lua (`lua_scripts/`), `mod-echoes-stats`,
  the SQL package. `mod-ale` is an external prerequisite. The ordinary install
  path never modifies it and fails with clear remediation if the required
  binding is absent; the separate `ale-compat` command is the only opt-in
  compatibility-patch path.
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

The Lua deployment contract is intentionally flat: only regular root-level
`lua_scripts/*.lua` files are runtime units. Subdirectories such as
`lua_scripts/tests/` contain developer fixtures and are excluded from live
deployment and manifest ownership.
# Split-root safety

For an unmistakable DML layout (`modules/` at the checkout root and both
`env/dist/lua_scripts/` and `env/dist/etc/modules/` present), omitted runtime
roots resolve to `env/dist`. Explicit `--lua-root` and `--config-root` always
win. `verify` also checks inspectable mod-ale source for the synchronous
`CharDBDirectExecute` API required by spending paths.

## Stock ALE compatibility preparation

Echoes 2.1.4 includes a minimal patch for official `azerothcore/mod-ale`
commit `9eeb1f3c47a81291548874fa4be2f4cde35e2ec3`. Inspect compatibility without
changing source:

```bash
installer/bin/echoes.sh ale-compat --azerothcore-root /path/to/azerothcore
```

Add `--apply` only after reviewing the output. The command checks the exact
revision and patch checksum, changes only the two documented ALE binding files,
and refuses unknown revisions. It does not build or restart the server. Rebuild
`worldserver`, restart it safely, run `echoes verify`, and require runtime
startup output `CharDBDirectExecute: YES` before treating spending as supported.
