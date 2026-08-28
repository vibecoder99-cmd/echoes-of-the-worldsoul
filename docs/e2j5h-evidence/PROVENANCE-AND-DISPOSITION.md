# E2j5h Dissolution Design — Provenance and Disposition

This directory holds design/test evidence from the E2j5h Dissolution
transaction-safety work (dated 2026-07-24/25). Two uncommitted local
edits sitting alongside this evidence — `lua_scripts/ap_forge.lua` and
`sql/schema/full_schema.sql` — were never committed to this repository
and have now been resolved rather than silently discarded. This note
records what they were and why.

## What was here

An earlier, working draft of the same durable two-phase Dissolution
pending-record design later finished in the WSL development repository
(`/home/dml/wow-server-playerbots`) and shipped in its current Lua/SQL.
The draft and its test evidence (`mock_db.lua`, `test_dissolution.lua`,
`test_fortitude_math.lua`, `results_dissolution.txt`,
`results_fortitude.txt`, `e2j5h-checkpoint-2026-07-25.md`,
`e2j5h-dissolution-safety-gate-report.md`,
`e2j5h-schema-preserved.diff`) were most likely developed and tested in
this repository as a standalone Lua sandbox, then the finished design was
carried into WSL and never ported back here or committed.

## Disposition

**Not promoted to current product code.** The exact diffs are preserved
as `superseded-draft-ap_forge.lua.diff` and
`superseded-draft-full_schema.sql.diff` in this directory, and the
working tree's `lua_scripts/ap_forge.lua` / `sql/schema/full_schema.sql`
have been restored to this repository's tracked HEAD. The current,
correct implementation of this design lives in the WSL repo today and
will reach this public repo only through the deliberate, explicitly
authorized 2.0 component sync (not yet performed).

### Why the draft was not kept as current code

- `ap_forge.lua` draft: uses inline `CharDBExecute(...)` calls followed
  by explicit `CharDBExecute("COMMIT")` after every statement, and a
  2-argument `AP.Forge.GrantDissolutionRewards(player, itemEntry)`
  signature. The current WSL implementation expresses the same design
  more completely via dedicated `AP.Forge.CreatePendingRecord` /
  `MarkPendingStatus` / `DeletePendingRecord` /
  `GrantDissolutionRewards(player, guid, accountId, itemEntry, rewards)`
  functions, and is reconciled against the live `ap04_db.lua`
  `REQUIRED_COLUMNS` schema contract (see the WSL repo's
  `docs/distribution/E2J16-CURRENT-SCHEMA-RECONCILIATION.md`).
- `full_schema.sql` draft: defines `ap_dissolution_pending` with
  `created_at`/`updated_at` timestamp columns and an `idx_guid_status`
  secondary index. Neither is required or read by the current live Lua
  (`ap04_db.lua`'s `REQUIRED_COLUMNS` lists only `guid`, `account_id`,
  `item_entry`, `item_instance_guid`, `quality`, `essence_reward`,
  `gold_reward`, `residue_reward`, `status`). The table also used
  `utf8mb3` here, superseded project-wide by `utf8mb4`/
  `utf8mb4_unicode_ci` per the DML target-database convention.

### One idea worth keeping for later

The draft's `created_at`/`updated_at` audit timestamps and
`idx_guid_status` index are **not currently required**, but are a
reasonable future enhancement candidate for `ap_dissolution_pending` if
a later phase wants audit-queryable pending-dissolution history rather
than just current status. Recorded here as a note, not adopted now, and
not blocking anything.

## One confirmed live defect, not fixed here (out of scope for this pass)

The draft's comment for `AP.API.DispatchHook`'s `OnForgeDissolve` payload
notes a bug fix: `pending.entry` was always `nil` (rows only ever set
`.itemEntry`, never `.entry`), corrected to `itemEntry` in the draft.

Checked against the current WSL `env/dist/lua_scripts/ap_forge.lua`: the
bug is **still present and live** in `AP.Forge.Dissolve`'s
`OnForgeDissolve` hook dispatch (`itemEntry=pending.entry`, always `nil`,
since `AP.Forge.Pending` entries only ever set `.itemEntry`). A second
call site in the same file (the direct/API dissolution path) already
uses a correct local `itemEntry` variable and is unaffected. This means
any consumer of the `OnForgeDissolve` hook currently receives `itemEntry
= nil` for every dissolution triggered through the normal interactive
gossip path.

This is a real, currently-shipping one-line defect, discovered as a side
effect of this reconciliation. **Not fixed as part of this pass** — it is
Lua/runtime work in the WSL repo, outside this checkpoint's scope
(public-repo cleanup and MPQ tooling only). Flagged for a separate,
explicitly authorized fix.
