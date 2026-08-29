# Echoes of the Worldsoul v2.0.0-rc1 — Release Notes

**Release Candidate.** Compatibility Verification & Operational Hardening is
complete: a real clean-room C++ compile matrix (Playerbots present and
absent), the public installer's own install/verify/upgrade/repair/uninstall
paths, and a live DML-compatible deployment have all been independently
verified. See `docs/COMPATIBILITY-ATTACK-DEFECT-LEDGER.md` for the full
evidence record. Public users with different AzerothCore/Eluna/MySQL setups
should still run the included test suites before deploying to production.

---

## What's New Since v1.6.0-rc1

**Production Client Companion.** A full graphical AddOn
(`EchoesOfTheWorldsoulBridge`) replacing the earlier chat-command-only
interface: Dashboard, Progression, Talents, World Threat, Crucible, Rack,
Legacy Forge, Visage, Codex/Search, Settings, and Accessibility all have
dedicated in-game panels, backed by a versioned client/server protocol.

**Optional Playerbots integration.** `mod-echoes-playerbots` bridges Echoes'
attunement/progression systems to AzerothCore Playerbots-driven characters
(awareness, retention, Rack interaction, progression spending, Dissolution)
without requiring Playerbots at all -- every Playerbots-dependent symbol is
guarded by `#ifdef MOD_PLAYERBOTS` and compiles to an inert no-op when
Playerbots isn't present, proven by an actual compiled build in both
configurations, not static inspection alone.

**Required engine-level stat module.** `mod-echoes-stats` moved
attunement/Crucible/Mastery stat application out of Lua-only approximation
and into a compiled, engine-level application layer.

**A real installer.** `installer/` (Python core, thin Bash/PowerShell
wrappers) replaces the manual copy-file-by-file process with tracked
install/verify/upgrade/repair/uninstall commands, a JSON manifest recording
exactly what Echoes owns, automatic backup-before-mutate on every change,
and support for both traditional single-root AzerothCore checkouts and
split Docker-style deployments (`--lua-root`/`--config-root`) where the
runtime distribution root differs from the source checkout.

**`patch-E.MPQ` client namespace.** Echoes' client patch now has its own
reserved, positively-identified slot, with automatic migration from the
legacy `patch-4.MPQ` naming used by prior releases.

**Idempotent, guarded SQL migrations.** `sql/schema/` is safe to re-run
against a fresh or already-current database with no changes, and applies
exactly the missing columns/tables against an older installed schema
without touching existing player data.

**Accessibility.** Client Companion includes a dedicated Accessibility
settings panel.

## Compatibility

**DML-compatible / tested with Dad's MMO Lab-style environments.** Echoes
was developed and live-certified against a Dad's MMO Lab-managed
AzerothCore + Playerbots deployment, including its Docker-based split
runtime layout. This is a compatibility statement about the environment
Echoes was tested against, not an endorsement by or affiliation with Dad's
MMO Lab.

**No custom WoW executable and no redistributed WoW client required.**
Echoes installs an additive client package (an AddOn plus a DBC patch
MPQ) into an existing, separately-obtained, compatible WoW 3.3.5a (build
12340) client. Echoes does not modify, redistribute, or claim the client
is unmodified by anything else you may have installed -- see
`INSTALL.md`'s client prerequisites.

**Playerbots load:** historically live-validated at approximately
1,700-2,000 concurrent bots against this exact integration over multiple
days of production operation, with current source/build/package
re-verification this release. See the compatibility ledger for the full
evidence chain.

## Known Limitations

- Automatic vanilla `Item.dbc` extraction (via the optional `mpyq`
  package) does not work against all real client archives -- many retail
  WotLK archives use an MPQ header format `mpyq` has incomplete support
  for. The installer's `--vanilla-dbc-path` fallback (extract once with
  any MPQ editor) is the reliable path for a fresh client install; see
  `INSTALL.md`.
- Live patch-load-order proof (the exact `patch-D`/`patch-E`/`patch-F`
  interaction) rests on documented community precedent, not an
  independently re-run fixture test this release.

## Install Order

See `INSTALL.md` for the full guide. Short version: use
`installer/bin/echoes.sh`/`echoes.ps1 install` (recommended, automates
everything below), or manually:

1. Copy `cpp_patch/mod-echoes-stats/` (required) and
   `cpp_patch/mod-echoes-playerbots/` (optional) into `modules/` and rebuild.
2. Run `sql/schema/*.sql` against `acore_characters`, in order.
3. Run `sql/data/world_items.sql` against `acore_world`.
4. Copy `lua_scripts/` to the server's Eluna script folder.
5. Patch the client `Item.dbc` and package as `patch-E.MPQ`.
6. Install the `EchoesOfTheWorldsoulBridge` client AddOn.
7. Restart the worldserver. Verify with `#ap` and `#aptest`.

## Important Warnings

- **Run SQL before enabling Lua scripts.** Some AzerothCore builds crash on
  missing tables/columns during DB queries.
- **C++ module rebuild required.** `mod-echoes-stats` statically links into
  `worldserver`; there is no binary-only install path.
- **No binaries or proprietary files included.** This release contains
  only source code, SQL, documentation, the installer, and the client
  AddOn -- no Blizzard client data of any kind.
- **GM tools are access-controlled.** All debug/admin commands require GM
  status.

## Version History

See `CHANGELOG.md` for the full feature evolution.

## License

GNU General Public License v3.0. Copyright 2025-2026 vibecoder99.
