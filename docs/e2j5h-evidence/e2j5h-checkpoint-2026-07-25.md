# E2j5h Checkpoint — 2026-07-25

Outcome: **DISSOLUTION REQUIRES JONAH — BOT EXCLUSION** (confirmed, accepted by Jonah).
Candidate preserved exactly as-is — no further code changes this checkpoint.

Preserved candidate:
- `lua_scripts/ap_forge.lua`: `6e06a5294860bc23b5a38099ba102abea8b743b8`
- `sql/schema/full_schema.sql`: `ee5050ee05b5ea0bce8958e0cbd85d0755b5517e` (unchanged)
- Tests: 66/66 passing (`docs/e2j5h-evidence/test_dissolution.lua`, `results_dissolution.txt`)

Summary, for the record:

- Dissolution's reward channels (essence, gold, Residue ledger) now use atomic
  single-statement grant-and-claim operations (`UPDATE ... JOIN`), not multi-statement
  sequences — this closes the duplicate-award gate without any schema change.
- The post-award/pre-COMPLETE fault injection point (Test 15) reconciled three times in a
  row without re-granting any reward channel.
- Partial issuance (Tests 16–18) is replay-safe: whichever channel(s) are still
  outstanding get granted exactly once; already-claimed channels are untouched across
  repeated reconciliation.
- The physical Residue item token is decorative only; `ap_residue.amount` is the sole
  authoritative value (nothing gates spending on physical item count). The token's narrow
  missed-grant window (Test 19) self-heals through the existing, already-shipped Residue
  reconciliation in the same login flow (Test 20, end-to-end).
- No schema change was required or made.
- **Isolated runtime verification and deployment remain pending** — nothing in this
  checkpoint has run against a live MySQL/worldserver/Eluna instance.
- **Enforced bot exclusion is unresolved and requires inspection in the authoritative
  production Playerbots/AzerothCore environment**, not this one. Confirmed with Jonah:
  production runs mod-playerbots, but the exact source/version and whatever Eluna binding
  (if any) it exposes for bot detection is unknown from this environment and cannot be
  guessed. No heuristic (session-nullness or otherwise) was substituted, and none should
  be.

Next authorized step (in the real production/build environment, not here):

1. Locate the exact mod-playerbots source and version used by production.
2. Inspect its C++ APIs and any registered Eluna extensions for authoritative bot
   detection.
3. Determine whether the existing build exposes a safe Lua predicate.
4. If none exists, propose the smallest explicit C++/Eluna bridge (e.g. an
   `IsPlayerBot()` predicate backed by Playerbots' authoritative AI ownership) — not a
   heuristic.
5. Test human rejection/acceptance behavior and bot denial before isolated runtime
   verification.

Stopped here. No deployment, no E2j6, no unrelated code changes.
