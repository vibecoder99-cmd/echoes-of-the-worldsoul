# E2j17 — Release Payload Bill of Materials

Every component shipped in the public repo, why it exists, and its
verified provenance as of the Phase B attack pass (2026-08-28, public
HEAD `b1cebab`). This is the checklist future syncs should re-satisfy to
prevent missing-file regressions.

## Lua scripts (`lua_scripts/`, 28 files)

Required. The complete Echoes server-side Eluna Lua package. Verified
byte-identical (line-ending differences normalized) to the current WSL
runtime authority (`env/dist/lua_scripts/`), file-for-file, with the one
deliberate, confirmed exclusion (`ap_gm_aether.lua`, DEVELOPMENT ONLY).
Load order is alphabetical (Eluna's own directory-scan behavior); the
`ap00`–`ap06` numeric-prefix bootstrap scheme guarantees compat/runtime/
DB-layer/UI-primitive/diagnostics load before every consumer, `ap_core`
before gameplay files, `ap_zzapi`/`zz_eluna_probe` load last. This
ordering is a property of the filenames themselves and is therefore
identical between WSL and public by construction.

## SQL package (`sql/schema/`, 6 files; `sql/data/`, 1 file)

Required. `00_preflight.sql` → `90_validation.sql`: the tracked, numbered,
guarded install package (18 tables), reconciled against the live
`ap04_db.lua` `REQUIRED_TABLES`/`REQUIRED_COLUMNS` contract — independently
re-derived this pass via direct grep of every `` `ap_...` `` reference
across current Lua source (18 distinct table names) and C++ source
(confirms `ap_schema_version` as the 19th, installer/compatibility-only
table). Zero missing, zero extra. `world_items.sql`: the guarded,
conflict-detecting item_template migration for entries 900010/900011.

## C++ modules (`cpp_patch/`, 2 module trees)

- `mod-echoes-stats/` (7 files): **required core**. Verified
  file-complete against WSL's `modules/mod-echoes-stats/` (0 missing,
  0 extra); the only difference is the deliberately-edited
  `conf/mod_echoes_stats.conf.dist` (public-release default
  `Enable=1`, corrected stale authorization language — confirmed
  intentional, diffed line-by-line).
- `mod-echoes-playerbots/` (45 files): **optional, compile-time
  self-gated**. Verified file-complete against WSL's
  `modules/mod-echoes-playerbots/` (0 missing, 0 extra, excluding the
  deliberately-omitted `.conf.dist.e2j5candidate` experimental variant);
  the only difference is the deliberately-edited
  `conf/mod_echoes_playerbots.conf.dist` (`CompatibleVersionPrefix`
  `"1.6."`→`"1.7."`, corrected stale evidence-path comments — confirmed
  intentional).
- `mod-ale`: **external prerequisite, deliberately NOT shipped**.
  Confirmed absent from tracked source (zero hits for any `mod-ale`
  path anywhere in the repo).

## Client Companion (`client_addon/EchoesOfTheWorldsoulBridge/`, 273 files)

Required (recommended install component). Verified byte-identical
(line-ending normalized) to WSL's production-locked
`client/AddOns/EchoesOfTheWorldsoulBridge/`, 273/273 files, with the one
deliberate, confirmed exclusion (`EchoesUI/Proof/SettingsProof.lua`,
dev-only A/B harness, not TOC-referenced). Every `.toc`-referenced file
verified present with exact case on a real case-sensitive Linux
filesystem (WSL), not just Windows' case-insensitive default. Asset
references verified: every `.tga` basename either matched directly in
Lua source or (for the `CRU_CHANNEL_PLATE_<letter>` family) confirmed
constructed via string concatenation, not a literal miss. 13 shipped
assets found with no Lua reference at all (`ProgressionLandmark.tga`,
`TalentsLandmark.tga`, `WorldThreatLandmark.tga`, `RACK_LOWER_CONTINUATION_RAIL.tga`,
6 `SHARED_*` files) — these are **pre-existing in WSL** (the tree is
byte-identical), match the already-documented frontend
Dead-Experiment-Ledger category (see the WSL repo's
`FINAL-WHOLE-CLIENT-AUDIT/`), and are not a packaging-introduced defect.

## DBC/MPQ tooling (`dbc_patch/`, 5 files)

Required (for anyone building a client patch). `patch_item_dbc.py`
(canonical DBC row construction), `mpq_writer.py` (deterministic archive
packaging), `build_patch_mpq.py` (orchestrator, targets `patch-E.MPQ`),
`test_mpq_writer.py`, `DBC_EDITING_NOTES.md`. Ships no Blizzard source
data.

## Installer (`installer/`, 24 files across `core/`, `bin/`, `tests/`)

Required (for anyone installing without doing it by hand). Seven
commands (`install`, `verify`, `upgrade`, `repair`, `uninstall`,
`client-package`, `discover`), zero load-bearing stubs. Thin Bash/
PowerShell wrappers confirmed to handle space-containing paths
correctly on both platforms this pass.

## Documentation (`README.md`, `INSTALL.md`, `CHANGELOG.md`,
## `RELEASE_NOTES_v1.6.0-rc1.md`, `docs/`)

`README.md`/`INSTALL.md`: minimum-necessary-corrected this arc, not a
full rewrite (deferred to release packaging). `CHANGELOG.md`/
`RELEASE_NOTES_v1.6.0-rc1.md`: preserved historical records, untouched.
`docs/`: E2j16/E2j17 evidence trail (component-sync manifest, MPQ/DBC
provenance, closeout, this BOM, the attack defect ledger).

## External prerequisites (not shipped, documented as required)

- **mod-ale** (Eluna fork, `LUA_VERSION=lua52`) — required for any
  Echoes Lua to run.
- **mod-playerbots** — required only if Playerbots integration is
  desired; Echoes Core has zero dependency on it.
- **Python 3** — required to run the installer and DBC/MPQ tooling.
- **`mysql` CLI** — required by the installer's SQL steps (external
  system binary, not a Python package).
- **`mpyq`** (optional Python package) — only needed for the
  installer's automatic vanilla-`Item.dbc` extraction from a client's
  stock archives; confirmed to fail with a clear message (not a crash)
  when absent, falling back to an explicit `--vanilla-dbc-path`.
- **A legally-owned WoW 3.3.5a (build 12340) client** — required to
  produce or receive `patch-E.MPQ`; never bundled.
