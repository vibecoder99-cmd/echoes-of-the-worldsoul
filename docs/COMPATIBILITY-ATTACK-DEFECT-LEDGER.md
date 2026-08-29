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

### DEFECT-04 (minor) — module test files not wired into ctest/CMake

- **Severity:** P3
- **Artifact:** `modules/CMakeLists.txt` (no test-discovery mechanism
  for module `tests/` directories); `modules/mod-echoes-playerbots/README.md`
  (documents only 1 of 8 test files, and implies all of them share a
  bare-`g++` standalone build pattern when one, `EchoesBotCacheTests.cpp`,
  requires the full core include tree).
- **Attack that found it:** Compile-matrix pass, module unit test
  verification (this pass).
- **User impact:** None to end users; a developer running `ctest` gets
  zero module test coverage without realizing it, and following the
  README's own documented command for `EchoesBotCacheTests.cpp`
  produces a misleading compile error.
- **Release blocking?** No.
- **Status:** OPEN — cosmetic/completeness, not fixed this pass (would
  require a build-system change, out of scope for a fix pass).

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

## Compile-level attack — RESOLVED this pass (real clean-room compile matrix)

- **Actual compile attack** (§17–18, compile level): performed for
  real this pass, not deferred. Set up a WSL Arch Linux toolchain from
  scratch (cmake, boost, openssl, MySQL client headers, gcc-15) and
  built two independent copies of the current source tree end to end:
  - **Config A (Playerbots present):** `worldserver`/`authserver`
    configured and built successfully. Resulting `worldserver` is a
    real 2.4 GB ELF executable that runs (`--version` prints
    `AzerothCore rev. 6c70e2dc7ef3+ ... (Playerbot branch)`) and
    contains 475 real `PlayerbotAI::`/`PlayerbotMgr::`/
    `RandomPlayerbotMgr::` symbols (the actual Playerbots engine),
    plus `mod-echoes-playerbots`'s `AddSC_EchoesPlayerbotsAwareness`
    and `mod-echoes-stats`'s `Addmod_echoes_statsScripts` — everything
    linked together.
  - **Config B (Playerbots absent):** the same source tree with
    `modules/mod-playerbots/` removed before configure. `-DMOD_PLAYERBOTS`
    correctly never appears in the CMake output. `worldserver`/
    `authserver` built and linked successfully — a real 1.57 GB ELF
    executable — with **zero** `PlayerbotAI::`/`PlayerbotMgr::`
    symbols, confirming the actual Playerbots engine is absent, while
    `mod-echoes-playerbots`'s own registration
    (`Addmod_echoes_playerbotsScripts`, `AddSC_EchoesPlayerbotsAwareness`)
    and `mod-echoes-stats`'s `Addmod_echoes_statsScripts` are still
    present and linked. This is the actual, compiled proof that
    `#ifdef MOD_PLAYERBOTS` gates real Playerbots-dependent code paths
    while leaving the rest of the module fully functional — not a
    grep-level inference.
  - The core's own bundled `unittest_suite` target (a pre-existing,
    unrelated `WorldMock`/gmock abstract-class build break in
    AzerothCore's own test source, triggered by `-DBUILD_TESTING=1`)
    was excluded by building the `worldserver`/`authserver` targets
    directly rather than `all`; this is an upstream core issue, not an
    Echoes/Playerbots defect, and is out of scope for this attack.
  - Two genuine, unrelated environment/toolchain defects were found
    and fixed **only in disposable local copies of the source, never
    in the live WSL runtime tree**: (1) a real prototype mismatch in
    vendored `deps/jemalloc` (`safety_check.h` declared
    `safety_check_set_abort` with unspecified arguments `()` while
    `safety_check.c` defines it taking `(const char *)` — a pre-existing
    jemalloc-snapshot bug, reproducible on both GCC 16.1 and GCC 15.3,
    unrelated to Echoes/Playerbots); (2) AzerothCore's `FindMySQL.cmake`
    needs the actual Oracle-API-compatible MySQL client library
    (`mysql_ssl_mode`, `mysql_stmt_bind_named_param`, etc.) — Arch's
    default `mariadb-libs` package does not provide these APIs, so
    `percona-server-clients` (which tracks the Oracle API) was used
    instead via explicit `-DMYSQL_INCLUDE_DIR`/`-DMYSQL_LIBRARY` cache
    variables. Neither fix touched any Echoes-owned file or the live
    WSL tree; both are one-time local toolchain/environment setup
    facts, recorded here for reproducibility.
- **Module unit tests** (new this pass): 7 of the 8 `.cpp` test files
  under `modules/mod-echoes-playerbots/tests/` are genuinely standalone
  (compile with a bare `g++ -std=c++17 -I../src`, per the pattern the
  module's own README documents for one of them) and all pass:
  `EchoesDissolutionPolicyTests` 42/42, `EchoesBotActionTypesTests`
  28/28, `EchoesBotCacheTests` — see below, `EchoesDispositionTests`
  26/26, `EchoesResidueSpendingPolicyTests` 14/14,
  `EchoesProgressionBudgetPolicyTests` 24/24,
  `EchoesProgressionSchedulerPolicyTests` 89/89,
  `EchoesLoginReconciliationTests` 11/11,
  `EchoesAwarenessTests` 13/13 — **247/247 standalone assertions
  passing**. One file, `EchoesBotCacheTests.cpp`, is not actually
  standalone (its production source transitively includes the full
  AzerothCore `Common.h`, unlike the other seven) and cannot be
  compiled with the documented bare `g++` pattern; its README should
  be corrected to not imply all module tests follow that pattern (P3,
  doc accuracy, not fixed this pass). Its underlying production source
  is nonetheless proven to compile correctly as part of the full
  `worldserver` build above. None of these 8 test files are wired into
  AzerothCore's own CMake/ctest integration — `modules/CMakeLists.txt`
  has no test-globbing mechanism for module `tests/` directories, so
  `ctest` never runs them; they must be invoked manually as documented.
  This is a real, minor completeness gap (P3) worth fixing post-2.0,
  not fixed this pass (would be a build-system change, out of scope
  for an attack/fix pass).
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
| P3 | 2 (DEFECT-03, DEFECT-04 — both open, cosmetic) |
| POST-2.0 | 0 new (existing deferred items unchanged) |

## Release blockers

None at P0/P1. DEFECT-01 and DEFECT-02 (both P2, both specific to the
**upgrade** path from a real prior public release, not fresh install)
are fixed and verified by a durable regression test this pass. No open
P2/P1/P0 defects remain. DEFECT-03 (P3, cosmetic unused import) remains
open by design — non-blocking.

---

## Final Live Certification Pass — client environment authority and evidence status

**Client authority (per explicit project direction, not independently
derivable from this session's filesystem inspection alone):**

- **`C:\Dad's MMO Lab Test WoW Client\`** — the authoritative current DML
  target used for current Echoes compatibility/live validation.
- **`C:\AzerothCore Client\`** — historical/alternate client, **non-
  authoritative for current DML certification**. Its exact historical
  origin/lineage is not independently proven by this session and is not
  claimed here. Both clients were observed (read-only) to currently carry
  byte-identical `patch-4.MPQ` file sizes and the `EchoesOfTheWorldsoulBridge`
  AddOn; per project direction, this shared content does not make the two
  clients equal authorities for certification purposes.

**Existing `Data\patch-4.MPQ` on the authoritative DML client:** confirmed
genuinely Echoes-owned. SHA-256
`2a9c38e589226d7c3ff84ef218e4a2d001801fcc9cf0e9252e6652ddcbc8bb4c`,
positively identified via `installer/core/mpq_conflict.py`'s
`identify_legacy_echoes_patch4()` — byte-exact match on both custom item
records (900010, 900011), confirmed against this real production file, not
only synthetic test fixtures. Safe for the installer's legacy-migration path
to convert to `patch-E.MPQ`.

**FORGE LIVE TEST:**
- Status: **USER-REPORTED LIVE PASS**
- Exact total/pass/fail counts: **not captured in this session**
- Independently witnessed by this Claude session: **NO**
- This is recorded as a user-reported result, not a session-verified one.
  It is not treated as an open/unknown functional defect for current
  certification scope, per explicit project direction. If exact evidence
  is needed for a future audit, rerun `#aptest forge` and capture the
  output.

**PACKAGE-EQUIVALENT SERVER BUILD/BOOT (section 5) — RESULT: PASS, with one
honestly-scoped limitation:**

Built a real `worldserver`/`authserver` from a genuinely bare AzerothCore
substrate (`modules/mod-echoes-stats`, `modules/mod-echoes-playerbots`, and
`lua_scripts/` all physically stripped before running the public
installer's own `install` command against it — not the WSL dev tree
directly). Verified by symbol inspection: `Addmod_echoes_statsScripts()`
and `Addmod_echoes_playerbotsScripts()` both present and linked, 475 real
`PlayerbotAI::`/`PlayerbotMgr::` symbols confirming the actual Playerbots
engine (not a stub) is linked in, matching the `--with-playerbots
--confirm-playerbots-compatible` install flags used.

Booted the resulting `worldserver` against a disposable, schema-seeded
MySQL instance (never the production database — confirmed no accidental
production connection succeeded; see safety note below). Result, in order:
Auth/Character/World/Playerbots database pools all opened and migrated
cleanly (1352 world updates, 28 Playerbots updates, zero SQL errors);
module configuration correctly listed `mod_echoes_stats.conf` and
`mod_echoes_playerbots.conf` among "Using modules configuration"; C++
script initialization completed with no errors. Boot then reached
`Failed to find map files for starting areas` and stopped — reproduced
identically across two independent runs, confirming this is the actual,
consistent point of failure, not a fluke. This is the same, already-
documented environment limitation from earlier in this pass (no extracted
client map/vmap/DBC data exists in this environment) — not a new defect.
Lua/Eluna initialization was not reached, since it occurs later in
AzerothCore's own boot sequence than map loading; **Lua-load verification
in this exact boot path remains unproven**, though the Lua file set itself
was already proven byte-identical to production source in an earlier pass.

**Safety note:** one intermediate boot attempt's config accidentally
carried `mod-playerbots`'s own default `PlayerbotsDatabaseInfo` pointing at
port 3306 (the same host port the live production `ac-database` container
listens on) with disposable-test credentials. The connection was rejected
("Access denied") — no access to the production database occurred — and
the config was immediately corrected to point only at the disposable
instance before any further boot attempt. Recorded here for transparency,
not because anything was actually touched.

**CLIENT PACKAGE REPRODUCTION (narrowed scope item 2) — RESULT: PASS:**

Built a fresh `client-package` from the public installer and compared it
file-by-file (SHA-256) against the AddOn actually deployed on the
authoritative DML client
(`C:\Dad's MMO Lab Test WoW Client\Interface\AddOns\EchoesOfTheWorldsoulBridge`).
Result: all 273 packaged files are byte-identical to the deployed files.
One file exists on the deployed client but not in the package or anywhere
in the tracked repo/history (`EchoesUI/Proof/SettingsProof.lua`) — confirmed
to be local, untracked dev-testing cruft left on the client machine
outside the normal packaging flow, not a packaging gap.

**Certification scope narrowed** (per explicit project direction) to:
installer/package output reproducing the known-good current DML state;
package-equivalent server build/start; package-equivalent Client Companion
behavior; patch-E migration/load validation against the authoritative DML
client (using its already-verified-good existing `patch-4.MPQ` payload,
not a from-scratch vanilla-client DBC rebuild); DML end-to-end
install/verify; remaining live/package checks. The generic-AzerothCore
claim is treated as already verified (clean PASS, see compile-matrix and
installer sections above) and does not require re-litigating the alternate
client's history as a release condition.

---

## Playerbots Stress Certification — historical evidence re-anchor

**PLAYERBOTS LIVE LOAD: HISTORICALLY VERIFIED — up to ~1,700–2,000 bots.**

A new large-scale live stress run was attempted this pass but blocked by a
genuine environment-safety constraint (see below), which prompted a
review of this project's own Obsidian historical record
(`C:\Second Brain\30 Software\AzerothCore\DML Playerbots Server\DML Baseline
Status.md`, `...\Attunement Plus\Playerbots.md`, `...\Attunement Plus\Lessons
Learned.md`). That record establishes the population question was already
answered, and at a higher scale than initially recalled:

- During phases E2j5e→E2j5h (2026-07-24 to 2026-07-26), the production
  container ran with `AC_AI_PLAYERBOT_RANDOM_BOT_AUTOLOGIN=1` live for
  multiple days, with **~1,647–1,914 bots online** confirmed on 2026-07-25,
  and separately **~1,835–1,998 bots** / **~1,998 bots confirmed online**
  at other checkpoints in the same window — i.e. genuinely close to this
  project's full configured ceiling, not a partial sample.
- Across that entire window: all three running containers
  (`ac-worldserver`, `ac-authserver`, `ac-database`) showed
  `RestartCount=0` and **zero new errors** at every checkpoint. No crash,
  no DB corruption, no compatibility failure is recorded anywhere in this
  window.
- The only issue on record is a **policy** discrepancy, not a technical
  one: the project's intended default is Playerbots **off** until
  high-impact gameplay gaps close, and autologin had been left `=1`
  against that intent. It was corrected back to `0` "per Jonah's
  instruction to keep Playerbots off by default" during the next
  deployment (E2j5h Stage 4) — a deliberate policy/workflow decision, not
  a rollback due to instability. This matches (and in fact exceeds, in
  scale) the "tested progressively, stopped for workflow reasons, not due
  to a compatibility failure" framing.
- Separately, the project's own history had already discovered and
  documented the exact env-var-vs-conf-file precedence issue rediscovered
  independently this session: a `playerbots.conf` file edit "is not a
  reliable way to get a small, controlled bot population online" (one
  attempt produced 416 accounts against an intended 2-3, root cause never
  found), while the `AC_AI_PLAYERBOT_MIN_RANDOM_BOTS`/`MAX_RANDOM_BOTS`
  environment-variable method was independently proven deterministic
  across three separate tests. The established pattern for a *controlled*
  checkpoint population was a temporary **side container**, not editing
  the main production container in place.

**Given this, the current ~1,800-bot-scale integration is classified
HISTORICALLY LIVE-VALIDATED, not untested** — the fact that this specific
Claude session did not personally reproduce that exact run does not reset
that evidence to zero, especially with current source/build/package
equivalence independently re-verified this pass (real compile-matrix
proof of both Playerbots configurations, DML/generic installer PASS,
byte-identical client package reproduction).

## Operational-hardening finding: container recreate risk (not a Playerbots product defect)

An attempt to run a *new* live stress session this pass required raising
`AiPlayerbot.MinRandomBots`/`MaxRandomBots`/`RandomBotAutologin` on the
live DML production deployment. Investigation found:

- `dml-start.sh`'s `restart` mode deliberately uses `docker start` (not
  `docker compose up`), specifically to avoid re-triggering the one-shot
  `ac-db-import`/`ac-client-data-init` containers on every restart — its
  own comment states this "was killing the database" historically.
- Because of this, `AC_AI_PLAYERBOT_*` environment variables (which take
  precedence over the `.conf` file for these specific settings, per
  AzerothCore's standard `ConfigMgr` env-var-priority behavior) are frozen
  for the life of the running container and cannot be changed by any
  config file edit or in-game/console command (`.rndbot reload` included)
  without an actual container recreate.
- `ac-db-import` was found in `Created` (not `Exited (0)`) state at audit
  time. A `docker compose up` touching either app service must resolve
  the full `depends_on` graph, including `service_completed_successfully`
  for `ac-db-import` — a state that a `Created` container does not
  satisfy, meaning a recreate would very plausibly re-run the fresh-install
  import path against the live, populated production database.
- **Decision: did not recreate the containers.** The temporary
  `AC_AI_PLAYERBOT_RANDOM_BOT_AUTOLOGIN`/`MIN_RANDOM_BOTS`/`MAX_RANDOM_BOTS`
  edits made in preparation (`docker-compose.override.yml` and
  `env/dist/etc/modules/playerbots.conf`, both backed up to
  `env/backups/e2j17-stress-cert-pre-enable-20260828T175150/` before
  editing) were reverted back to `0`/`0`/`0` to match the established
  intended configuration, since they were inert anyway (the running
  containers never picked them up) and would otherwise be a "future
  surprise" if left in place ahead of a later, legitimate recreate.

**This is recorded as operational-hardening documentation for future DML
operations, not a Playerbots or Echoes product defect:** any future
container recreation against this populated environment must first
resolve the `ac-db-import` state (or use an isolated side-container/backup
strategy, matching this project's own historical pattern for controlled
bot-population testing) rather than a casual `docker compose up`/recreate.

**~1,800-bot maximum stress this pass: NOT PERFORMED / NOT REQUIRED for
2.0**, given the historical evidence above and the safety decision not to
force a recreate for incremental evidence value alone.
