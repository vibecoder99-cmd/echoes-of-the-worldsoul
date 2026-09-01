# Chaos Mode: Wrath Progression Research and Real Backend

Date: 2026-08-31
Ruleset: Chaos v1

## Evidence and authority

- AzerothCore `Creature::SelectLevel` (current local revision `52f58186a533`) computes max health from `CreatureBaseStats::GenerateHealth`, then applies the configured rank-rate returned by `_GetHealthMod`.
- `CreatureBaseStats::GenerateHealth` is `ceil(BaseHealth[expansion] * ModHealth)`.
- The live server sets Normal, Elite, Rare, Rare Elite, and World Boss HP rates to `1`. Rank therefore adds no further health on this deployment; template `HealthModifier`, expansion-specific base HP, level, class, and difficulty templates already produce the hierarchy visible through `UnitHealth`.
- Public AzerothCore references:
  - https://github.com/azerothcore/azerothcore-wotlk/blob/master/src/server/game/Entities/Creature/Creature.cpp
  - https://github.com/azerothcore/azerothcore-wotlk/blob/master/src/server/game/Entities/Creature/CreatureData.h
  - https://github.com/azerothcore/wiki/blob/master/docs/creature_template.md
  - https://github.com/azerothcore/database-wotlk/blob/master/sql/base/player_classlevelstats.sql
- Local `acore_world.creature_classlevelstats` shows warrior-class creature base HP growing from 42 at level 1 to 5,342/9,215/12,600 at level 80 for Classic/TBC/Wrath expansion columns. Template modifiers then produce the large endgame step.
- Local raid examples: Diseased Young Wolf 42 native HP; Lord Marrowgar templates 6,972,500 to 31,376,250; Yogg-Saron templates 10,999,998 to 43,999,264.
- Player max health is not level alone: AzerothCore combines class-level base health with race/class level stats, stamina, gear, auras, and modifiers. The client-provided final `UnitHealth` remains the display authority.

## Echoes durable-data audit

| System | Durable truth | Chaos contribution | Reason |
|---|---|---:|---|
| Attunement | Character/item unique fully-attuned rows | Yes | Permanent, explainable character development. |
| Mastery | Character rank plus best-effort spend audit | Yes, reconstructed from rank | Rank is authoritative; cumulative rank cost backfills deterministically even if old audit rows are incomplete. |
| Crucible | Permanent account/category investment | Yes | Permanent development and not a wallet. Shared account contribution is reported honestly. |
| Talents | Current ranks; GM reset refunds Essence | No | Refundable and would enable score decreases/double counting. |
| Rack | Capacity and current contents | No | Infrastructure, not direct character power. |
| Forge | Currency, dissolution records, catalyst state | No | Transaction/infrastructure state, not retained character strength. |
| Essence/Residue | Current balances | No | Wallets must not become Chaos Power. |
| Slot XP | Durable specialization XP | No in v1 | Potentially farmable activity and not yet proven as permanent power independent of Attunement. |
| World Threat | Reversible risk setting | No | Difficulty preference, explicitly not character development. |
| Visage | Cosmetic selections/unlocks | No | Presentation, not power. |

## Model comparison

- Current-state-derived: reconstructible, deterministic, no fictional history, and cannot be reset-loop farmed when only permanent inputs are selected.
- Lifetime cumulative: strongest monotonic fantasy, but historical Attunement event detail does not exist and adding an event ledger would invent unequal backfill.
- Hybrid: useful only if future mechanics require non-reconstructible lifetime credit; unnecessary for v1.

Decision: current-state-derived v1. It is the smallest truthful model and is naturally backfilled for every existing character.

## Exact v1 formula

```text
mastery_basis(rank) = sum(floor(400 * n^1.5), n = 1..rank)

attunement_contribution = fully_attuned_unique_items * 5,000
mastery_contribution    = mastery_basis * 25
crucible_contribution   = total_permanent_account_investment * 10

chaos_power = 1,000
            + attunement_contribution
            + mastery_contribution
            + crucible_contribution
```

Magnitude is `floor(log_1000(chaos_power))`: 1=K, 2=M, 3=B, 4=T, then Qa, Qi, and later orders. It changes notation only.

The backend sends `chaos_power` as a decimal string. The Lua 5.1 client derives a four-significant-digit mantissa and order from string length without converting the full integer through `tonumber`.

`chaos_scale` is basis points applied after the accepted target-level taper:

```text
chaos_scale = 1000 + min(250, 25 * magnitude)
effective_multiplier = interpolated_level_multiplier * chaos_scale / 1000
```

Level anchors remain `(1,1000), (10,600), (30,300), (50,180), (60,140), (70,120), (80,100)`. Skull targets use level 80. The client no longer adds classification multipliers because final native HP already contains the local server's authoritative template/rate result.

## Existing-character backfill examples

These are real local rows, not invented profiles:

| Character | Level | Attuned | Mastery | Crucible | Breakdown | Power | Magnitude |
|---|---:|---:|---:|---:|---|---:|---:|
| Nikar | 1 | 0 | 0 | 1,000 | 1,000 base + 0 + 0 + 10,000 | 11,000 | I |
| Uramestuk | 4 | 2 | 0 | 1,000 | 1,000 + 10,000 + 0 + 10,000 | 21,000 | I |
| Geoff | 3 | 2 | 0 | 1,000 | 1,000 + 10,000 + 0 + 10,000 | 21,000 | I |
| Brus | 4 | 14 | 4 | 1,000 | 1,000 + 70,000 + 170,225 + 10,000 | 251,225 | I |

This directly explains why Brus exceeds the other low-level characters without awarding power merely for level.

## Health sanity readings for a Brus viewer

Brus is Magnitude I, so the v1 scale basis is 1,025. Representative full-health readings derived from local authoritative templates are:

| Target | Native HP | Chaos HP |
|---|---:|---:|
| Diseased Young Wolf, level 1 | 42 | 43,050 (43.1K) |
| Lord Marrowgar base | 6,972,500 | 718,167,500 (718M) |
| Lord Marrowgar difficulty 1 | 23,706,500 | 2,441,769,500 (2.44B) |
| Lord Marrowgar difficulty 3 | 31,376,250 | 3,231,753,750 (3.23B) |
| Yogg-Saron difficulty 1 | 43,999,264 | 4,531,924,192 (4.53B) |

For every row, current and maximum HP use the identical multiplier, preserving `current/max` exactly before display rounding.

## Storage and protocol

- One guarded `TINYINT(1) chaos_enabled DEFAULT 0` column was added to `ap_mastery`; no new table or event ledger.
- State fields: `chaos_enabled`, decimal-string `chaos_power`, `chaos_magnitude`, `chaos_scale`, ruleset, and deterministic contribution fields.
- Action: `chaos_toggle 0|1`; server validates, writes synchronously, acknowledges, and the client requests authoritative state.
- Existing `aether` state reading was corrected to the repository's `AP.DB.GetUInt64` accessor while touching this query. Chaos Power never uses a 32-bit DB accessor.

## Damage/healing presentation contract

Implemented combat presentation selects the destination/recipient's effective
multiplier at event time for supported damage, healing, and prevention.
Floating output and the live Blizzard Combat Log remain presentation-only;
native amounts, signs, and combat resolution are authoritative.

## Limitations and verdict

- Coefficients are v1 design choices fitted to truthful Echoes state and broad Wrath magnitude shape; they are not Blizzard balance constants.
- Crucible is account-wide, so its contribution is shared by characters on that account.
- Power arithmetic is exact for practical current ranges but backend Lua remains IEEE-754; a future ruleset must introduce integer-string arithmetic before totals approach `2^53`.
- Automated backend/client/schema tests pass and the live server starts with schema readiness. The user manually verified persisted-ON relog, character switching, Mage/Warlock spell behavior, floating output, live Combat Log values, broad NPC samples, Magnitude I believability, and stable post-fix tooltips.

Verdict: **GREEN** for the defined Echoes 2.1.0 scope, with documented P2 boundaries.
