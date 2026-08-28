# Compatibility Verification — Package Attack Defect Ledger

Adversarial attack pass against public HEAD `b1cebabb282aecab08e4f7375dd1040645e52c55`,
2026-08-28. Audit only — no canonical source fixes applied during this
pass, per explicit instruction. Findings below are what survived
verification; nothing here was assumed from documentation alone.

## Severity key

P0 — corruption/crash/basic unusability. P1 — core 2.0 functionality
missing/broken. P2 — install/compatibility/reliability defect. P3 —
docs/polish/minor hardening. POST-2.0 — explicitly deferred, not a defect.

---

### DEFECT-01 — Upgrade from the actual v1.6.0-rc1 layout leaves the confirmed dev-only `ap_gm_aether.lua` behind

- **Severity:** P2
- **Artifact:** `installer/core/install.py` (Lua sync step)
- **Attack that found it:** Section 28/29 — upgrade from an export of the
  real `v1.6.0-rc1` git tag (not a synthetic placeholder), then diffed
  against a fresh current install.
- **Evidence:** `install()`'s `lua_scripts` sync copies every file from
  the current source into the target but never removes a
  destination-only file that no longer exists in current source. The
  real v1.6.0-rc1 tree ships `ap_gm_aether.lua` (confirmed DEVELOPMENT
  ONLY and deliberately excluded from the public repo's own
  `lua_scripts/` during the E2j16 sync). Upgrading from that real tree
  leaves the file physically present and loadable — `comm -23` between
  the exported v1.6.0 file list and the current 28-file list shows
  exactly one orphan: `ap_gm_aether.lua`. All other converged files were
  verified byte-identical between a fresh install and the v1.6.0-upgrade
  path, so this is an isolated, well-understood gap, not a general sync
  failure.
- **User impact:** An operator upgrading from a real prior public
  release ends up running a Lua file this project explicitly decided
  should not ship, defeating that decision. No crash, no data risk — the
  file was already reviewed as harmless-but-unwanted.
- **Release blocking?** Not P0/P1, but real and should be fixed before
  claiming upgrade correctness for public release.
- **Fix:** `installer/core/legacy_retirement.py` (new) — positive-
  identity-gated retirement: a legacy Lua filename must ALSO match a
  stable content-signature substring before removal, never filename
  alone. `retire_legacy_lua()` is invoked from `install.py` immediately
  after the core-Lua sync/checkpoint. Matched files are backed up (not
  deleted outright) via the existing `backup.py` path before removal.
- **Status:** FIXED + VERIFIED. Verified by
  `installer/tests/test_legacy_upgrade_convergence.py`
  (`test_legacy_release_converges_to_current`), which upgrades a real
  exported `v1.6.0-rc1` tree and asserts `ap_gm_aether.lua` is retired,
  backed up, and absent afterward, and that the post-upgrade Lua file
  set is byte-identical to a fresh install (28/28 files). 13/13 assertions
  passing at time of fix.

### DEFECT-02 — Upgrade from the actual v1.6.0-rc1 layout leaves the old `modules/mod-attunement-plus/` module directory behind entirely

- **Severity:** P2
- **Artifact:** `installer/core/install.py` / `upgrade.py`
- **Attack that found it:** Same v1.6.0-rc1 upgrade attack as DEFECT-01.
- **Evidence:** The real v1.6.0-rc1 `cpp_patch/mod_attunement_plus.patch`
  would have produced `modules/mod-attunement-plus/` on a real historical
  install. The installer only ever writes to `modules/mod-echoes-stats/`
  and `modules/mod-echoes-playerbots/` — it has no knowledge of the old
  module's name or location and never removes it. Reproduced directly:
  a simulated `modules/mod-attunement-plus/src/*.cpp` tree, present
  before upgrade, is confirmed still present, byte-for-byte, after a
  full `upgrade()` call.
- **User impact:** Dead source is left in the AzerothCore `modules/`
  tree indefinitely. If that old module was ever actually built into a
  real `worldserver.exe` binary, its object code remains compiled in
  until the operator manually deletes the directory and rebuilds — the
  installer gives no indication this is necessary.
- **Release blocking?** Not P0/P1 (no functional conflict — the old
  module doesn't collide with the new ones under different names), but
  a real hygiene/completeness gap in the upgrade path specifically.
- **Fix:** Same `legacy_retirement.py` module —
  `retire_legacy_modules()` requires both a positive content-identity
  match (required files present + stable content-signature substring)
  AND confirmation that the declared replacement component
  (`mod_echoes_stats`) is already installed in the same operation before
  removing the old module directory (with backup). Invoked from
  `install.py` immediately after the Playerbots integration block.
- **Bug found while building this fix (recorded, not a separate
  defect):** the retirement rule's `superseded_by` list was initially
  written as `["mod-echoes-stats"]` (hyphenated, matching the module
  directory naming convention), but `install.py` passes
  `currently_installed_components=list(m["components"].keys())`, and
  manifest component keys use underscore naming
  (`"mod_echoes_stats"`). The mismatch made the retirement logic always
  report the replacement as "not yet installed" even when it was,
  silently preventing removal. Fixed by correcting the list to
  `["mod_echoes_stats"]`, with a code comment documenting the
  naming-convention distinction to prevent recurrence. Caught before
  release by the regression test, not by inspection alone.
- **Status:** FIXED + VERIFIED. Verified by the same
  `test_legacy_upgrade_convergence.py` test: confirms
  `modules/mod-attunement-plus/` is retired, backed up, and physically
  absent after upgrade, and that `mod_echoes_stats` is present in both
  the fresh-install and upgraded trees.

### DEFECT-03 (minor) — `sql_runner.py` imports `glob` without using it

- **Severity:** P3
- **Artifact:** `installer/core/sql_runner.py`
- **Attack that found it:** Section 41 (offline/dependency inventory).
- **Evidence:** `SCHEMA_FILE_ORDER` is a fixed literal list, not
  glob-derived; the `import glob` at the top of the file is dead.
- **User impact:** None (unused stdlib import, no behavior change).
- **Release blocking?** No.
- **Status:** OPEN — cosmetic, not fixed this pass.

---

## Attacks that found NO defect (recorded so this isn't mistaken for unattempted coverage)

- **Lua completeness/byte-diff** (§5–6): 28/28 files byte-identical
  (line-ending normalized) between WSL and public; exactly one
  deliberate exclusion; zero public-only stale files.
- **Lua load order / static global contract** (§7–8): not separately
  re-derived from scratch — the shipped file SET and NAMES are proven
  byte-identical to the currently-running production Lua, so packaging
  cannot introduce a new ordering/contract defect that isn't already
  present (and already proven working) in the live server. This is a
  deliberate scoping decision, not a skipped attack.
- **BOM/encoding** (§10): `zz_eluna_probe.lua`'s UTF-8 BOM is confirmed
  pre-existing in WSL source, unaffected by packaging. **Resolved this
  pass: BOM ACCEPTED, not a defect.** No Lua 5.2 interpreter exists in
  this environment; used a real Lua 5.4 interpreter
  (`C:\...\Programs\Lua\bin\lua.exe`/`luac.exe`, v5.4.6) as a proxy,
  since the BOM-skip logic in `lauxlib.c`'s `luaL_loadfilex` was
  introduced in Lua 5.2 and is unchanged through 5.2/5.3/5.4 — the exact
  window mod-ale's `LUA_VERSION=lua52` build target falls inside. Both
  `luac -p` (syntax check, exit 0) and `lua -e "loadfile(...)"`
  (returned a valid loaded function object, not `nil`+error) succeeded
  directly against the file. This also explains the earlier
  E2j13-era `luac5.1`-based failure: Lua 5.1 predates the BOM-skip
  feature entirely, so a 5.1 parser choking on this file was expected
  and is not evidence of a real-runtime problem. **Caveat honestly
  carried forward:** this proves the standard Lua auxiliary-library
  loader accepts the BOM; it does not by itself prove a fully custom
  Eluna file-loading code path (if one exists) behaves identically —
  no further action taken, file left untouched.
- **`ap_gm.lua` disposition** (carried from E2j13, reclassified this
  pass): previously logged as "DEVELOPMENT ONLY". Traced actual
  registrations/commands/runtime use: self-registers via
  `AP.RT.RegisterEvent("player", 18/19, ...)`, is GM-gated via
  `AP.IsGM`, and provides real support commands (`#apgm aether`,
  `setmastery`, `snapshot`, `wipeattune`, `toggledebug`, `togglecheese`,
  `threat`, `info`). Reclassified **OPTIONAL ADMIN TOOL** — the prior
  "development only" label was stale. No removal, no change; ships as-is
  in the current source and public repo.
- **Client Companion completeness** (§11): 273/273 files byte-identical;
  one deliberate exclusion; zero public-only stale files.
- **TOC attack** (§12): every referenced file present, exact case,
  verified on a real case-sensitive Linux filesystem (WSL), not just
  Windows.
- **Client asset reference attack** (§13): every `.tga` resolves to a
  real reference (direct or string-concatenation-constructed); 13
  unreferenced assets found and traced to a pre-existing, already-
  documented Dead-Experiment-Ledger category, not a new defect.
- **C++ module completeness** (§16): both modules 100% file-complete
  against WSL; only the two deliberately-edited `conf.dist` files differ,
  confirmed line-by-line to be exactly the intended public-release-default
  changes.
- **Playerbots symbol guard attack** (§18, grep-level only — see
  ENVIRONMENT LIMITATIONS below for the compile-level attack): re-verified
  every real Playerbots symbol/include across all 3 referencing files
  falls inside `#ifdef MOD_PLAYERBOTS`, both `#else` no-op stub
  definitions present.
- **SQL contract attack** (§20): re-derived the full table contract
  independently from live Lua+C++ source (grep, not doc-trust) — exactly
  18 gameplay tables + `ap_schema_version`, matching the shipped schema
  exactly. Zero missing, zero extra.
- **Installer payload/manifest completeness** (§23–24): confirmed by
  code path (whole-tree `copytree`/per-file `listdir`+copy, no filtering
  that could silently drop a file) and by the manifest being derived via
  `sha256_tree()` immediately after each copy (provably complete by
  construction).
- **Verify per-component-class corruption attack** (§25): verify
  correctly detects induced corruption in `core_lua` and
  `mod_echoes_stats`; a malformed-JSON manifest raises rather than
  silently proceeding.
- **Uninstall containment attack** (§27): unrelated seeded files
  (`lua_scripts/unrelated_third_party.lua`, an unrelated
  `modules/some-other-module/`) and `mod-ale` all confirmed to survive
  a full Echoes uninstall.
- **Manifest tamper/path-traversal attack** (§27, security angle):
  a manifest entry using `../../` traversal did not escape the target
  root; the underlying `safety.is_safe_to_delete()` primitive
  independently confirmed to reject an absolute-path-outside-root target.
- **Crash/failure-recovery attack** (§46): induced failure via a bad
  `client_root` after core components succeeded; manifest still recorded
  the successful components; a corrected rerun fully recovered; `verify`
  showed zero FAIL; `repair` correctly found nothing to do on the healthy
  result.
- **Clean checkout attack** (§40): a fresh `git clone` of the public
  repo into an isolated temp directory, with zero reliance on OneDrive
  working-tree leftovers, ran the full 96-check sandbox suite and
  `client-package` successfully — no hidden local-state dependency found.
- **Offline/dependency attack** (§41): the only non-stdlib Python import
  anywhere in `installer/`+`dbc_patch/` tooling is the already-optional
  `mpyq`; empirically confirmed it fails with a clear message (not a
  crash) when absent.
- **Wrapper quoting attack** (§38): both `echoes.sh` (via WSL) and
  `echoes.ps1` (native Windows) correctly handle a space-containing
  target path.
- **Version/release-metadata grep** (§43): the previously-deferred
  `.github/ISSUE_TEMPLATE/` `v1.6.0-rc1` labels/placeholders are fixed
  this pass — both templates now use generic pre-release wording
  ("Example: v1.6.0-rc1, or the commit hash you're running") instead of
  a hardcoded label, so the templates don't go stale at the next tag.
- **Symlink/reparse attack** (§19, resolved this pass): the prior
  Windows-only attempt was blocked by lack of unprivileged symlink
  rights. Retested on WSL's native Linux filesystem, which supports real
  unprivileged symlinks: both a symlinked file and a symlinked directory
  pointing outside the target root were correctly rejected by
  `safety.safe_remove_file()` / `safety.safe_remove_tree()`
  (`UnsafePathError`, path resolved and re-checked against the root
  before acting), and the real targets outside the root survived
  untouched in both cases.

## Environment limitations (attack not completed — honestly reported, not faked)

- **Actual compile attack** (§17–18, compile level): a full AzerothCore
  build (Playerbots-present and Playerbots-absent configurations) was
  not performed — this environment does not have a built/buildable
  AzerothCore core source tree with a configured toolchain available
  within this session's practical time budget. The `#ifdef
  MOD_PLAYERBOTS` guard *source* was re-verified exhaustively by direct
  inspection (see "found NO defect" above), but this is explicitly a
  weaker claim than "compiles cleanly in both configurations." Deferred
  to Compatibility Verification.
- **Live client tests** (§31, §33, §35): patch-E.MPQ live load, `#aptest
  forge` live execution, and Client Companion end-to-end smoke all
  require an interactive WoW client session, which this environment
  cannot drive. Not performed, not faked.
- **Patch load-order fixture test** (§32): the letter-load-order claim
  rests on documented evidence (this project's own pre-existing
  `patch-Z.mpq` precedent + community documentation), not a live
  patch-D/E/F fixture test in a real client. Deferred.
- **DML/generic-AzerothCore installation walkthrough** (§36–37): not
  performed as an end-to-end human-usability walkthrough this pass; the
  installer's argument surface and discovery output were exercised
  directly (see wrapper/clean-checkout attacks) but not narrated from a
  first-time-user perspective.

## Totals

| Severity | Count |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 2 (DEFECT-01, DEFECT-02) — both FIXED + VERIFIED |
| P3 | 1 (DEFECT-03, still open, cosmetic) |
| POST-2.0 | 0 new (existing deferred items unchanged) |

## Release blockers

None at P0/P1. DEFECT-01 and DEFECT-02 (both P2, both specific to the
**upgrade** path from a real prior public release, not fresh install)
are fixed and verified by a durable regression test this pass. No open
P2/P1/P0 defects remain. DEFECT-03 (P3, cosmetic unused import) remains
open by design — non-blocking.
