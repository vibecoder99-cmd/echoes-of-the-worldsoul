# E2j5h Dissolution Safety Gate — Report

Date: 2026-07-25
Evidence directory: `docs/e2j5h-evidence/` (this directory — durable, git working tree, not scratchpad)

## Outcome

**DISSOLUTION REQUIRES JONAH — BOT EXCLUSION**

The duplicate-award / silent-item-loss gate is now closed (see below). The one remaining
blocker is bot exclusion: no bot-detection mechanism is discoverable anywhere in the
accessible codebase, and none can be safely invented or approximated.

## Fortitude (unchanged this round)

`FORTITUDE CONTRACT VERIFIED — NO RESTORATION DIFF REQUIRED`. Not touched this round.
`lua_scripts/ap_sinks.lua` and `cpp_patch/mod_attunement_plus.patch` remain byte-identical
to `HEAD` (`git diff --stat` empty).

## Preserved schema

`sql/schema/full_schema.sql` was **not modified** this round or any prior round.
Working-tree blob hash: `ee5050ee05b5ea0bce8958e0cbd85d0755b5517e` (unchanged from the
prior checkpoint). No schema change was needed to close the duplicate-award gap — see
"Why no schema change was needed" below.

## Duplicate-award / silent-item-loss analysis

### The exact operations available

`ap_forge.lua` (Eluna Lua) has no cross-statement transaction primitive — `BEGIN`/`COMMIT`
issued as separate `CharDBExecute` calls are not guaranteed to land on the same MySQL
connection under AzerothCore's async worker pool (documented in this file's own
`AP.Sinks.Invest` comment). However, a **single** SQL statement is atomic under InnoDB's
autocommit — this is a real MySQL/InnoDB guarantee, independent of anything Eluna exposes.

The pre-existing (previous-checkpoint) `GrantDissolutionRewards` spanned reward issuance
across multiple independently-committed statements/systems:
`ap_mastery` UPDATE, `player:SetCoinage()` (in-memory) + `SaveToDB()`, `ap_residue` UPDATE
+ `player:AddItem()` (in-memory) + its own `SaveToDB()`, then a final separate
`ap_dissolution_pending` status UPDATE. A crash between any of these could re-grant on
the next login's reconciliation pass. This was correctly identified as a real gap, not
acceptable-by-precedent.

### What was closed, and how

Each reward channel's "grant" and "claim" (mark this amount as already granted) were
folded into **one** multi-table `UPDATE ... JOIN` statement against existing tables —
no schema change:

- **Essence** → `ap_mastery.aether`: `UPDATE ap_mastery m JOIN ap_dissolution_pending p ... SET m.aether = m.aether + p.essence_reward, p.essence_reward = 0 WHERE ... AND p.essence_reward > 0`
- **Gold** → `characters.money` directly (not through `player:SetCoinage`, which is
  in-memory-first and can't be joined atomically to our claim row). Verified against
  AzerothCore's actual base schema (`data/sql/base/db_characters/characters.sql`):
  `guid` INT UNSIGNED PK, `money` INT UNSIGNED. Same atomic-UPDATE pattern.
  `player:SetCoinage()` is still called afterward, but only as a best-effort sync of the
  live in-memory object — the DB write is already the durable source of truth, so a crash
  between the UPDATE and the sync call loses or duplicates nothing (next login loads the
  correct value fresh from DB).
- **Residue ledger** → `ap_residue.amount` (the authoritative value — `GetResidue` /
  `SpendResidue` read only this, never a physical item count): same atomic-UPDATE pattern.

Because each of these is a single MySQL statement, InnoDB guarantees it either fully
commits or doesn't happen — there is no partial-execution state to recover from. A replay
after any crash point re-reads the pending row's remaining-amount columns; whatever is
already 0 (already claimed) makes that statement's `WHERE ... > 0` guard a no-op.

**This is not claimed to be atomic across the whole reward-grant sequence** — it explicitly
is not (three separate atomic statements, not one transaction spanning all three). It is
exactly-once **per channel**, proven by test, which is what the gate requires.

### Physical Residue item (disclosed, not "fixed")

`player:AddItem()` for the decorative physical Residue token is not a raw SQL statement
and cannot be joined atomically with the claim row. It is now gated on whether *this*
call is the one that performed the ledger claim (checked before the atomic UPDATE runs),
so it cannot be duplicated. The one remaining case: a crash strictly between the ledger
UPDATE committing and the `AddItem` call running leaves the physical token ungranted —
a **missing-token risk, not a duplicate-award risk**, and it does not affect the
authoritative ledger value (nothing in this codebase gates spending on physical item
count — only `ap_residue.amount`). Test 20 confirms this specific gap is self-healing in
the real integrated login flow: the pre-existing, already-shipped Residue `clean_exit`
reconciliation in this same file independently compares ledger vs. physical count and
tops up any shortfall on next login, regardless of source.

### Why no schema change was needed

The fix used only existing columns (`ap_dissolution_pending.essence_reward` /
`gold_reward` / `residue_reward`, repurposed from "snapshot to grant" to "remaining
amount to grant" — same values, same column types, converges to the original meaning on
the non-crash path) and existing tables (`ap_mastery`, `characters`, `ap_residue`). No
`ALTER TABLE`, no new column, no new table. `sql/schema/full_schema.sql` was not touched.

### Targeted fault injection (as required)

Test suite: `test_dissolution.lua`, run via real Lua 5.4 against the actual
`ap_forge.lua` source (not a reimplementation), mocked DB in `mock_db.lua`.
**66/66 passed.** Full output: `results_dissolution.txt`.

Specifically requested points:
- **Test 15** — crash constructed at exactly "all rewards granted, COMPLETE not yet
  recorded," reconciled **3 times in a row**: no reward channel re-granted.
- **Tests 16–17** — partial issuance (essence-only granted; essence+gold granted),
  reconciled repeatedly: only the outstanding channel(s) are granted, previously-granted
  channels are provably untouched.
- **Test 18** — 5 repeated reconciliations from a fully-outstanding `RECORDED` row: each
  channel granted exactly once, never a multiple.
- **Test 19** — isolates the one disclosed gap (physical token) and proves it is a
  missing-token characteristic, not a duplicate-token one.
- **Test 20** — proves the disclosed gap self-heals end-to-end via the real registered
  login handler.

Also carried forward from the prior checkpoint (not re-claimed as new): eligible/
ineligible/equipped/missing item, repeated confirmation, rapid duplicate request,
crash-before-removal, crash-after-removal-before-ledger, audit payload correctness, all
6 reward-quality tiers.

### File hashes

- `lua_scripts/ap_forge.lua` — working tree git blob: `6e06a5294860bc23b5a38099ba102abea8b743b8`
  (prior checkpoint, before this round's atomic-claim rewrite: `08f481429c61dfbf3cb2f8e614a78f595caba6b8`)
- `sql/schema/full_schema.sql` — working tree git blob: `ee5050ee05b5ea0bce8958e0cbd85d0755b5517e` (unchanged)
- `lua_scripts/ap_sinks.lua`, `cpp_patch/mod_attunement_plus.patch` — unchanged (`git diff --stat` empty)

## Bot exclusion — investigation

Per instruction: inspected the actual AzerothCore/Eluna build surfaces and installed
modules on this machine for an authoritative bot-detection mechanism, rather than
inventing one.

- This repo (`echoes-of-the-worldsoul`) is Lua-only content; it has no Eluna or
  Playerbots source of its own.
- The only other AzerothCore checkout on this machine (`~/Desktop/azerothcore-wotlk`) has
  a `modules/` directory containing **only the module scaffolding template**
  (`CMakeLists.txt`, `ModulesLoader.cpp.in.cmake`, `how_to_make_a_module.md`, etc.) — no
  Eluna module, no Playerbots module, actually present. Confirmed via directory listing.
- No `IsBot`, `GetPlayerbotAI`, or equivalent binding is referenced anywhere in this
  repo's Lua (`grep` across `lua_scripts/` — zero matches) or in
  `cpp_patch/mod_attunement_plus.patch`.
- **Lower shared boundary considered and rejected**: checking `player:GetSession()` for
  nilness, or any similar "does this look like a real network session" heuristic, is not
  reliable — Playerbots-style bot integrations are specifically designed to fabricate a
  session/Player object that looks legitimate to the rest of the engine, so nothing at
  that boundary reliably distinguishes a bot without module-specific knowledge this
  environment does not have access to. Guessing at one would be inventing an API, which
  was explicitly ruled out.
- Trigger-surface note (does not substitute for real exclusion): `AP.Forge.Dissolve` is
  only reachable through this addon's own gossip-menu dispatch
  (`AP.Forge.OnSelect`), and nothing in this repo drives that dispatch on behalf of a bot
  AI today. That is incidental behavior of what currently calls into this code, not an
  enforced guarantee, exactly as flagged in the prior checkpoint.

**Conclusion: no reliable bot-detection mechanism exists anywhere accessible from this
environment, and no safe lower-boundary substitute exists without inventing one or
touching unrelated systems.** This is a genuine blocker requiring a decision from Jonah:

1. Does the actual target production server run mod-playerbots at all?
2. If yes, what Eluna binding (if any) does that specific module/fork expose for bot
   detection, so this code can check against something real?
3. If no reliable binding exists even on the real production module, is "incidental,
   not enforced" an acceptable interim state for this specific gossip-menu-only feature,
   or is a different mitigation required (e.g., server-side config disabling bot gossip
   interaction generally)?

## Not done this round (per stop instruction)

No runtime deployment, no production work, no broad documentation reconciliation, no
password rotation, no E2j6.
