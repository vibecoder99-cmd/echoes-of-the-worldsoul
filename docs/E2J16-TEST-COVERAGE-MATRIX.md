# E2j16 — Test Coverage Matrix

Final closeout numbers (rerun at closeout, 2026-08-28): **96 PASS / 0 FAIL
/ 1 SKIP**. Unchanged from the prior checkpoint's count — re-running
before closing confirmed nothing regressed between checkpoint and
closeout.

All tests live in `installer/tests/test_installer_sandbox.py` plus
`dbc_patch/test_mpq_writer.py` (12 checks, covered under the earlier
MPQ/DBC reproducibility checkpoint, not re-counted here to avoid double
counting — see `E2J16-MPQ-REPRODUCIBILITY.md` in the WSL repo).

## Classification

| Test function | Type | What it proves |
|---|---|---|
| `test_discovery_azerothcore_root` | UNIT / FILESYSTEM | AzerothCore-root marker detection (modules/, mod-ale, mod-playerbots, DML-style `dml-start.sh`), present and absent cases |
| `test_discovery_client_root` | UNIT / FILESYSTEM | Compatible-3.3.5a-client marker detection, present and absent cases |
| `test_prereq_mod_ale` | UNIT / FILESYSTEM | mod-ale presence/absence, remediation text on absence |
| `test_mpq_conflict_policy` | UNIT | `resolve()`'s 3 pure-logic outcomes; confirms no `force_overwrite` parameter exists |
| `test_legacy_patch4_identification` | SANDBOX / PACKAGE | Byte-exact fingerprint recognizes a genuine Echoes payload (built via a real `patch_item_dbc.py` run, not a hand-built fixture), rejects a foreign payload, handles a missing file without raising |
| `test_patch_e_build_and_legacy_migration` | SANDBOX / FILESYSTEM | patch-E.MPQ build via `mpq_writer`; legacy patch-4.MPQ → patch-E.MPQ migration (genuine payload migrated + old removed only after verification; unrelated payload left untouched) |
| `test_config_materialize` | UNIT / FILESYSTEM | Fresh-create with override; merge-forward adds new keys without touching existing user tuning |
| `test_safety_containment` | UNIT / FILESYSTEM | Path-traversal rejection, root-as-target rejection; symlink-escape rejection **SKIPPED** (see below) |
| `test_full_install_and_verify_sandbox` | DATABASE / SANDBOX / FILESYSTEM | Fresh install (18/18 schema tables, Lua + mod-echoes-stats copied, config defaulted to `Enable=1`), repeat install, `verify()` zero-FAIL |
| `test_repair_and_uninstall_and_upgrade` | DATABASE / SANDBOX | Legacy pre-manifest upgrade; Playerbots present/requested/unconfirmed vs. present/confirmed matrix; repair (missing auto-restored, mismatched reported-only by default, explicit override restores); uninstall (owned files removed, mod-ale/mod-playerbots untouched, database retained) |
| `test_partial_install_failure_recovery` | DATABASE / SANDBOX | Induced SQL-target failure raises correctly; manifest still records the components that succeeded before the failure (progressive checkpointing); a corrected subsequent install fully recovers |

## SKIPPED

`test_safety_containment`'s symlink-escape case: this Windows environment
refuses unprivileged symlink creation (`OSError`/`NotImplementedError`
from `os.symlink()`), so the test reports `[SKIP]` rather than fabricating
a pass. The **implementation** (`safety.safe_remove_file`/
`safe_remove_tree` refusing a symlink target) exists and is reviewed, but
is not runtime-exercised on this machine. Carried into Compatibility
Verification as an explicit deferred item — see
`E2J16-DISTRIBUTION-PACKAGING-CLOSEOUT.md`.

## MANUAL / DEFERRED LIVE (not automated, not claimed as covered)

- patch-E.MPQ live-client load confirmation.
- `#aptest forge` live execution (confirming the `itemEntry` hook fix in
  a running game).
- Clean-room C++ compile matrix (Playerbots-present; Playerbots-absent /
  `MOD_PLAYERBOTS` undefined).
- `zz_eluna_probe.lua` UTF-8 BOM behavior against the live Lua 5.2 loader.
- Symlink/reparse-escape runtime test on an environment capable of
  creating the required link type.

None of these were implemented or faked during E2j16 closeout — all are
explicitly deferred to Compatibility Verification.
