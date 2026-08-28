# E2j16 — Distribution & Packaging Implementation: Closeout

Status: **CLOSED / VALIDATED**. Closed 2026-08-28.

## Problem statement

Echoes of the Worldsoul's 2.0 gameplay, backend, protocol, and graphical
Client Companion were all complete, but the project was not installable
by anyone other than its current operator: no tracked/repeatable
database install path existed, the client patch (`Patch-4.MPQ`) was
built by two ad hoc, off-repo, personal-path-hardcoded scripts, and the
public-facing release repository was stale (v1.6.0-rc1) and structurally
disconnected from current development.

## Original P2 release blockers

**P2-1 — No tracked/repeatable database install path.** The versioned
SQL package existed only inside a historical backup snapshot
(`env/backups/e2f1/.../package/sql/`), not on any live, repeatable
migration path. **CLOSED.** Reconciled against the live `ap04_db.lua`
schema contract (adding the previously-uncaptured `ap_dissolution_pending`
table), ported into the WSL repo's `echoes/sql/` and then into the public
repo's `sql/schema/` as the single tracked authority. Fresh-install,
repeat-install, and upgrade-from-a-simulated-legacy-schema all validated
against disposable databases, never the live production database.

**P2-2 — Patch-4.MPQ build depended on off-repo personal scripts.**
**CLOSED / SUPERSEDED.** The two ad hoc scripts (`create_patch_mpq.py`,
`add_residue_to_dbc.py`, hardcoded to a client path that no longer exists
on this machine) are retired. Replaced by: the already-tracked
`dbc_patch/patch_item_dbc.py` (canonical DBC row construction, unmodified
by this phase), a newly-extracted `dbc_patch/mpq_writer.py` (deterministic
MPQ packaging, corrected StormLib encrypt/decrypt), and — after a
mid-phase namespace change — the **patch-E.MPQ** client-patch slot
(replacing patch-4, a common first custom-patch slot other mods also
reach for) with a legacy-migration path and installer integration.

## Public-repo discovery and authority split

Mid-phase, a separate, real, public GitHub repository
(`vibecoder99-cmd/echoes-of-the-worldsoul`, v1.6.0-rc1, already known to
the project since E2f1 but never reconciled forward) was found to already
substantially embody the release-layout architecture E2J13b's blueprint
proposed. Rather than build a second, competing distribution tree inside
the WSL development repo, the authority model was set as:

- **WSL repo** (`/home/dml/wow-server-playerbots`): current
  behavioral/integration truth.
- **Public repo** (`C:\Users\felle\OneDrive\Desktop\echoes-of-the-worldsoul`):
  release/distribution authority.

The public repo's pre-existing dirty state (an abandoned draft of the
same E2j5h Dissolution work, plus shell debris) was resolved
deliberately — preserved as historical evidence
(`docs/e2j5h-evidence/`), not discarded — before any new work began.

## Schema reconciliation

`echoes/sql/` (WSL) / `sql/schema/` (public): 18 required tables,
reconciled table-by-table and column-by-column against the live
`ap04_db.lua` `REQUIRED_TABLES`/`REQUIRED_COLUMNS` contract, not
resurrected as-is from the historical backup. One gap found and closed:
`ap_dissolution_pending` (added post-E2f1 by the E2j5h Dissolution work)
had never been captured in any SQL package; its definition was derived
directly from live `ap_forge.lua`/`ap_tests.lua` call sites.

## DBC/MPQ provenance

- Canonical DBC patcher: `dbc_patch/patch_item_dbc.py` (already tracked,
  unmodified this phase; builds both custom item records — 900010
  Worldsoul Echo Fragment, 900011 Worldsoul Residue — from a genuinely
  vanilla `Item.dbc`, with a 6-point self-check).
- Canonical MPQ writer: `dbc_patch/mpq_writer.py` (extracted from the
  retired ad hoc scripts' `create_mpq()`, corrected StormLib
  encrypt/decrypt, path-parameterized, zero hardcoded paths).
- Rebuilt archive proven byte-identical to the previously-live known-good
  archive.
- No Blizzard source DBC data is shipped anywhere in tracked source; the
  vanilla `Item.dbc` is always either extracted from the operator's own
  client's stock archives or supplied explicitly.

## patch-E namespace decision

`patch-4.MPQ` was replaced with **`patch-E.MPQ`** ("E" for Echoes) as
Echoes' own reserved client-patch slot, to avoid colliding with the
common first custom-patch slot other mods/servers also use. Evidence for
letter-named-patch load support: this project's own pre-existing
`patch-Z.mpq` documentation (predates this installer work) plus
converging community documentation of WoW 3.3.5a's known patch-loading
algorithm. **This has not been independently confirmed via a live client
launch** — status is explicitly **TOOLING/PAYLOAD VERIFIED, LIVE CLIENT
LOAD CERTIFICATION DEFERRED TO COMPATIBILITY VERIFICATION.** A legacy
`patch-4.MPQ` from a prior Echoes install is migrated forward
automatically, but only when positively identified by a byte-exact
payload fingerprint (never by filename) — an unrelated `patch-4.MPQ` is
left completely untouched, and an unrelated `patch-E.MPQ` blocks the
install outright with no force-overwrite option anywhere in the ordinary
path. General MPQ/DBC merging across independent third-party patches is
explicitly out of scope for 2.0 — documented, not solved.

## Current component synchronization

The public repo now carries current 2.0 truth, synced from WSL and
reconciled component-by-component (not assumed identical): server Lua
(28 files, including the previously-missing `ap00`–`ap06`
bootstrap/protocol layer and the confirmed load-bearing `ap_botapi.lua`;
one confirmed dev-only file, `ap_gm_aether.lua`, removed), the SQL
package, `mod-echoes-stats` and `mod-echoes-playerbots` (replacing the
single-file patch targeting a module name that no longer exists), and
the full 273-file production-locked graphical Client Companion
(replacing the pre-graphical 2-file bridge). `mod-ale` is documented as
an external prerequisite, never vendored.

## Playerbots architecture

- **Echoes Core** (required): Lua, `mod-echoes-stats`. `mod-ale` is an
  external prerequisite.
- **Playerbots integration** (optional): `mod-echoes-playerbots`.
  Compile-time self-gated via `#ifdef MOD_PLAYERBOTS` throughout (every
  real symbol/include usage re-verified directly against current
  source — the earlier E2J13 boundary-doc finding of an unguarded
  dependency was stale, superseded by an already-applied E2j14
  Workstream B fix). Default **disabled**
  (`EchoesPlayerbots.Enable = 0`); the installer copies the module and
  only enables it when the operator explicitly passes
  `--confirm-playerbots-compatible` — never inferred from
  `mod-playerbots` merely being present. This does not make Playerbots a
  global Echoes requirement.
- `mod-echoes-stats` was reclassified **PRODUCTION REQUIRED** (its
  original "not authorized for production" notice was stale, dated to
  an early E2j3 milestone; it implements the entire advertised Crucible
  effect lineage and was already live-enabled in the DML environment).
  Public default: `EchoesStats.Enable = 1`.
- **DML posture:** DML-compatible — designed and tested against the
  DML-style environment (detected via the real, non-personal
  `dml-start.sh` marker file). This is not an official Dad's MMO Lab
  endorsement.

## Installer commands

All seven implemented, sandbox-tested, zero load-bearing stubs remaining
(confirmed by an explicit `NotImplementedError`/`TODO`/`FIXME`/
`placeholder`/`stub` search across `installer/` — the only hits are a
historical README reference, an exception-type name, and test-fixture
strings):

- **install**: Core required (Lua + mod-echoes-stats + SQL, refuses with
  remediation if mod-ale is absent) + optional Playerbots + recommended
  Client Companion/patch-E.MPQ.
- **verify**: read-only, manifest/file-hash/schema-version/patch-E/
  Playerbots-state checks, PASS/WARN/FAIL.
- **upgrade**: thin wrapper over `install()`'s own backup-before-replace
  and idempotent-SQL behavior; tested against a representative
  pre-manifest legacy (v1.6.0-style) layout.
- **repair**: missing files restored automatically; hash-mismatched
  files reported only by default (a changed file may be intentional
  customization), restored only with an explicit opt-in; `.conf` files
  never touched (config merge-forward is the correct tool there).
- **uninstall**: manifest-scoped removal only; database retained by
  default (uninstalling Echoes does not delete player progression);
  never touches mod-ale, mod-playerbots, or any unrelated content;
  `--purge` explicitly out of scope.
- **client-package**: produces the Client Companion bundle plus either a
  built patch-E.MPQ or instructed manual-build steps; ships no Blizzard
  data.
- **discover**: read-only target inspection.

## Backup / ownership / safety model

- Every mutating step backs up its target before overwriting
  (`backup.py`), formalizing this project's own historical
  `env/backups/` convention as automatic behavior.
- `safety.py`: every destructive path (repair, uninstall) is resolved
  and re-checked for containment under its expected root immediately
  before acting — a tampered manifest or a substituted symlink cannot
  redirect a deletion outside the intended tree. The symlink-escape
  **implementation** exists and is reviewed; the runtime test is
  **skipped** on this Windows environment (no unprivileged symlink
  creation) — not live-tested, carried into Compatibility Verification.
- Manifest ownership: `verify`/`repair`/`upgrade`/`uninstall` all read
  from `echoes-install-manifest.json`, never guess ownership from paths
  or filenames.

## Two real bugs found and fixed during this phase

1. **Manifest failure-safety.** Previously, the manifest was written
   only once, at the very end of `install()` — a failure partway through
   (e.g. a bad SQL target) left components that were actually copied to
   disk completely unrecorded. Fixed with a `checkpoint()` call after
   every major mutation stage. Covered by
   `test_partial_install_failure_recovery`.
2. **Backup timestamp collision.** The original second-resolution
   timestamp caused two same-component backups landing in the same
   wall-clock second to collide (`shutil.copytree` raising
   `FileExistsError` on the second call) — hit for real during this
   phase's own Playerbots-matrix testing. Fixed with microsecond
   precision. Both fixes are exercised by the current test suite, not
   just described.

## Test results

**96 PASS / 0 FAIL / 1 SKIP** (rerun at closeout; unchanged from the
prior checkpoint). Full classification: `docs/E2J16-TEST-COVERAGE-MATRIX.md`.
The one skip (symlink-escape runtime test) is an honest environment
limitation, not a fabricated pass.

## Deferred to Compatibility Verification

A. patch-E.MPQ live-client load confirmation.
B. `#aptest forge` live execution (confirming the `itemEntry` hook fix
   — WSL commit `6c70e2dc7`).
C. Clean-room C++ compile matrix: Playerbots-present, and
   Playerbots-absent/`MOD_PLAYERBOTS`-undefined where practical.
D. `zz_eluna_probe.lua` UTF-8 BOM behavior against the live Lua 5.2
   loader.
E. `ap_gm.lua` DEVELOPMENT ONLY classification / release disposition
   (currently shipped, matches `ap_gm_aether.lua`'s classification which
   WAS removed — flagged, not resolved).
F. `.github/ISSUE_TEMPLATE/` v1.6.0-rc1 label/placeholder cleanup
   (requires a version decision out of scope here).
G. Symlink/reparse-escape runtime test on an environment capable of
   creating the required link type.

None of these were implemented or faked during closeout.

## Exact commit SHAs (public repo, chronological)

`ab5ac81` MPQ writer/tests/orchestrator · `2bb48f6` E2j5h evidence
preservation · `4f08f20` 2.0 component sync audit manifest · `6a89dce`
Lua sync · `6fde121` SQL package replacement · `e3d1533` C++ module sync
· `83cbc38` Client Companion replacement · `c6286a6` README/INSTALL
minimum corrections · `4fef0d1` sync manifest status record · `8fd6989`
installer core infrastructure · `0aaa14a` install/verify/command surface
· `c0650e7` client/MPQ install logic · `642e985` Bash/PowerShell
wrappers · `8e0aab2` sandbox test suite · `f04c2db` installer README ·
`52c3a16` patch-E rename (dbc_patch) · `4706024` patch-E namespace +
legacy migration (installer) · `ccafcdb` safety primitives + manifest
checkpointing · `637c276` upgrade/repair/uninstall implementation ·
`20d0b68` repair/uninstall/upgrade/safety test coverage · `6ab88c9`
README status update.

WSL repo: `2d9535caa` (E2j16 SQL package), `9d2d76097` (public-repo
reconciliation + MPQ evidence), `6c70e2dc7` (Forge `itemEntry` fix).

## Verdict

**E2j16 — CLOSED.** Both original P2 blockers (database provenance, MPQ
provenance) are closed. The installer implements all seven commands with
zero load-bearing stubs, backed by 96 passing sandbox/database/filesystem
tests. Remaining live-certification items are explicitly deferred to
Compatibility Verification, not treated as E2j16 blockers.
