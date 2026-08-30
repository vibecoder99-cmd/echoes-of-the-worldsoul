# Module Compatibility

This document tracks Echoes of the Worldsoul's compatibility with other
AzerothCore/Playerbots ecosystem modules. It exists because "we tested this"
and "we think this should probably work" are different claims, and mixing
them erodes trust faster than just being slow.

## 1. Scope and Philosophy

Echoes is not claiming universal compatibility with every AzerothCore
module in existence — that claim isn't verifiable and wouldn't be honest
if made. Instead, this document tracks specific, named module combinations
against a strict evidence bar, and separately lists modules we intend to
test next because real users are likely to run them alongside Echoes.

If a module combination isn't listed here at all, that means exactly one
thing: it hasn't been evaluated yet. It is not a claim that it doesn't
work, and it is not a claim that it does.

## 2. Evidence-Status Legend

| Status | Meaning |
|---|---|
| **TESTED** | Empirical combined build/runtime evidence exists — the modules were actually compiled together and exercised, not reasoned about from source alone. |
| **SERVER TESTED / CLIENT MERGE REQUIRED** | Server-side integration is empirically verified. A known client-side data conflict exists, with a proven compatibility approach that requires an extra generated artifact. |
| **PARTIAL** | Important layers were tested; a specific, named path remains unresolved. |
| **TARGET** | Selected as a priority for future testing. No compatibility claim of any kind is made yet. |
| **HIGH-RISK TARGET** | Selected as a priority, and flagged in advance as likely to involve deep semantic interaction (e.g. item-instance mutation) that will need especially careful testing. |
| **NOT YET TESTED** | Exactly that. |

We do not use the word "compatible" for anything at TARGET status or below.

## 3. Current Tested Combinations

### Playerbots (`mod-playerbots`)

**Status: TESTED.** This is Echoes' primary, historically load-bearing
integration target, and the strongest evidence in this document:

- Real clean-room C++ builds completed with Playerbots present (475 real
  Playerbots engine symbols linked into the resulting binary) and with
  Playerbots absent (zero engine symbols, module still fully functional)
  — this is Echoes' optional-integration guarantee, proven by compiling
  both configurations, not inferred from `#ifdef` guards alone.
- Historically ran live in production at approximately 1,700–2,000
  concurrent bots over multiple days, with no Echoes compatibility
  rollback recorded.
- Current 2.0 source, build, and installer package paths were
  independently re-verified for this release.

This is tested against the documented AzerothCore/Playerbots environment
used for this release — **not a claim of support for every Playerbots
fork or configuration in existence.** See
[docs/COMPATIBILITY-ATTACK-DEFECT-LEDGER.md](COMPATIBILITY-ATTACK-DEFECT-LEDGER.md)
for Echoes' own release-verification evidence (a separate, internal
audit — not about third-party modules).

### mod-individual-progression

**Status: SERVER TESTED / CLIENT MERGE REQUIRED.** See §4 below for the
full breakdown.

## 4. mod-individual-progression — Details

**Tested target:** [`ZhengPeiRu21/mod-individual-progression`](https://github.com/ZhengPeiRu21/mod-individual-progression),
branch `master`, commit `df1016444abcc21d025885282799ba76bebea627`.

This is one specific revision of one specific fork. Others in its ~136
forks were not evaluated, and future commits to this same repository are
not automatically covered by this entry.

### Server-side — empirically verified

- Combined build (Echoes + mod-individual-progression + Playerbots)
  compiles and links successfully
- Zero database table collision between Echoes' own tables and IP's
  schema
- Echoes' permanent attunement snapshots correctly capture
  mod-individual-progression's item stat adjustments
- The engine-applied stat math was independently hand-calculated and
  matched the live engine's output exactly across all six stat channels
- Ordinary item-instance enchant bonuses are confirmed excluded from
  permanent snapshots, verified with a real, server-validated enchant
  applied live — not inferred from source alone
- Same-account, cross-character snapshot sharing behaves correctly
- Restart persistence holds: snapshots and item data survive a full
  restart unchanged
- A same-source-tree control build with mod-individual-progression
  physically removed was also verified, confirming Echoes has no hidden
  dependency on it

### Client data — known conflict, with a proven fix

mod-individual-progression's **optional** `patch-S` and `patch-V` client
patches each ship their own `DBFilesClient\Item.dbc`. Echoes' own client
patch (`patch-E.MPQ`) also supplies an `Item.dbc`. WoW 3.3.5's client
loads single-letter patches in strict alphabetical order, and DBC
overriding replaces the whole file — it does not merge rows. This means
installing Echoes' patch alongside IP's optional patch-S/patch-V as two
independent files does not work: whichever loads later wins entirely,
and the other's item rows are gone from the client's perspective.

This was confirmed by resolving the actual client patch-load order
programmatically (not by reasoning about filenames) and inspecting the
real, winning archive's contents:

- Installing patch-E + patch-S (or patch-V) independently: IP's archive
  wins, and Echoes' custom item entries are absent from the resolved
  `Item.dbc`.
- **The fix is a merged `Item.dbc`:** built from IP's own `Item.dbc` as
  the base, with Echoes' item rows added on top using Echoes' existing,
  unmodified patch-generation tooling. All of IP's original rows were
  independently verified byte-identical after the merge; Echoes' two
  custom entries are present and correctly formed.
- The merged artifact must be packaged as a **late-loading, correctly
  named** patch (the tested prototype used `patch-Z.MPQ`) so it loads
  after both patch-E and patch-S/V and wins for the file both need.
  **A patch file must use the client's exact single-letter naming
  convention (`patch-<A–Z>.MPQ`) to be auto-loaded at all** — a
  descriptively-suffixed name like `patch-Z-compat.MPQ` is silently
  ignored by the client's own patch discovery. This was found and
  corrected during testing, not assumed correct on the first attempt.
- Under `DBC.EnforceItemAttributes = 0` (the setting mod-individual-progression's
  own documentation requires), the server booted cleanly and correctly
  resolved item data for both mods' entries through its real,
  production item-lookup code path.
- **Do not simply "rename Echoes' patch-E to load later"** as a
  workaround — that only reverses which mod loses its `Item.dbc` data.
  The merge is the actual fix; reordering two independent whole-file
  providers is not.

### What has not been observed

- Exact icon/model appearance in a live, graphical client session
- Raw WoW network protocol packet framing against an actual client
  (the server-side data resolution this depends on has been verified;
  the wire-level round trip to a real game client has not)

Neither of these has been claimed as verified anywhere in this document
or in Echoes' release materials. **The merged-`Item.dbc` compatibility
path exists, has been validated at the data layer, and is not yet
packaged into an automated end-user installer step** — manual packaging
guidance may still be refined before this becomes a one-command install
option.

### Current wording

> Server-side compatibility with mod-individual-progression has been
> empirically verified for the tested revision. If mod-individual-progression's
> optional patch-S or patch-V client patch is used, Echoes requires a
> merged `Item.dbc` compatibility patch so both mods' client item data
> survive. The merged data path has been validated headlessly; final
> graphical presentation has not been manually spot-checked.

## 5. Target Matrix

| Module | Category | Status | Main interaction surface |
|---|---|---|---|
| [`mod-playerbots`](https://github.com/liyunfan1223/mod-playerbots) | Core ecosystem / bots | **TESTED** | Attunement/progression awareness for bot-controlled characters; see §3 |
| [`ZhengPeiRu21/mod-individual-progression`](https://github.com/ZhengPeiRu21/mod-individual-progression) | Progression / items | **SERVER TESTED / CLIENT MERGE REQUIRED** | `item_template` changes; `Item.dbc` collision in optional patch-S/V |
| [`azerothcore/mod-transmog`](https://github.com/azerothcore/mod-transmog) | Appearance / item state | TARGET — not yet tested | Item appearance/display state; possible interaction with attunement item identity |
| [`azerothcore/mod-autobalance`](https://github.com/azerothcore/mod-autobalance) | Scaling / solo & small-group | TARGET — not yet tested | Creature/player scaling; potential interaction with Echoes' own power stacking |
| [`azerothcore/mod-solo-lfg`](https://github.com/azerothcore/mod-solo-lfg) | Solo ecosystem | TARGET — not yet tested | Low expected direct conflict; high relevance to solo-server audiences |
| [`NathanHandley/mod-ah-bot-plus`](https://github.com/NathanHandley/mod-ah-bot-plus) | Economy / bots | TARGET — not yet tested | Auction-house economy; custom Echoes items/currencies; bot purchasing behavior |
| [`azerothcore/mod-aoe-loot`](https://github.com/azerothcore/mod-aoe-loot) | QoL / loot | TARGET — not yet tested | Loot hooks; expected low direct risk |
| [`ZhengPeiRu21/mod-challenge-modes`](https://github.com/ZhengPeiRu21/mod-challenge-modes) | Endgame / scaling / rewards | TARGET — not yet tested | Difficulty scaling and reward interaction; potential power-stacking overlap |
| [`azerothcore/mod-progression-system`](https://github.com/azerothcore/mod-progression-system) | Realm progression | TARGET — not yet tested | Global item/world progression changes via bracket-based script/SQL activation — **architecturally distinct from mod-individual-progression**; do not conflate the two |
| [`azerothcore/mod-solocraft`](https://github.com/azerothcore/mod-solocraft) | Solo scaling | TARGET — not yet tested | Player/group stat scaling; potential stacking with Echoes' own permanent bonuses |
| Random-enchant / reforge-style item-mutation modules | Item mutation | **HIGH-RISK TARGET** | Item-instance vs. item-template mutation; direct relevance to snapshot semantics and the risk of permanent-power leakage from what should be temporary bonuses. No specific module is named here yet — flagged as a category to watch for, not a claim about any particular repository. |

## 6. Testing Methodology

Every entry above `TARGET` in this document is backed by at least one of:

- An actual combined compile (both modules' source present, a real build
  produced, not just "the code looks like it would compile")
- An actual combined runtime (both modules loaded in the same running
  server, exercised, with real log/query evidence)
- Direct binary/byte-level inspection of the artifacts in question,
  where the compatibility question is about file formats rather than
  running code (e.g. the `Item.dbc` merge)

Testing happens in disposable, isolated environments — never against the
project's own live production deployment. "TESTED" always means the
combination was actually run together at least once; it never means
"read the source and it looked fine."

## 7. How to Report a Module Combination

If you run Echoes alongside a module stack that isn't listed here, please
open an issue with the exact module repositories and commits, your
configuration, and what you observed. Real-world combinations are what
determine testing priorities — this list grows based on what people
actually run, not guesswork about what might be popular.

We can't promise every requested combination will be tested or
supported, but a concrete report with exact versions is always more
useful to us than a general request.

## 8. Version / Fork Caveat

Every compatibility statement in this document is scoped to the exact
revision named. AzerothCore, Playerbots, and third-party modules all have
active forks and ongoing development. A module passing testing today does
not guarantee a later commit to the same repository — or a different
fork of it — behaves identically.

## 9. No Universal Compatibility Guarantee

Echoes of the Worldsoul does not claim to be officially supported by
AzerothCore, approved by Playerbots, approved by any third-party module
maintainer, or compatible with "all modules." Every claim in this
document is scoped to a named module, a named revision, and a named test
methodology — nothing more.
