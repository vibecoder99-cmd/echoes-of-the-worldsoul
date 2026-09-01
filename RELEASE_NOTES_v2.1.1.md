# Echoes of the Worldsoul v2.1.1 — Rack Spending & Installer Reliability Hotfix

Echoes 2.1.1 is a forward hotfix for the 2.1.0 Chaos Mode release. Existing
2.1.0 server operators should upgrade if players use Attunement Rack expansion.

## Fixed

- Essence-paid Rack upgrades no longer report success unless the currency debit
  and capacity increase are both durably verified.
- Legacy `#ap` and Client Companion Rack routes now converge on the same
  currency-specific, authoritative result.
- Guarded Rack mutations reject stale balances, stale capacity, replayed
  requests, zero-row writes, database failures, and post-write mismatches.
- Caught write-action exceptions now leave safe, actionable server logs.
- The installer validates the required source-inspectable ALE synchronous write
  API and automatically selects an unmistakable split `env/dist` runtime.
- Verification reports provably installer-owned files under prior runtime roots
  without deleting them.

No progression wipe or client replacement is required. Protocol version remains
1. The ChromieCraft client distribution is not implicated in this server-side
Rack defect.
