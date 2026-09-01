# Chaos Mode Architecture — 2.1.0

Native AzerothCore combat remains authoritative. Chaos V1 is a viewer-side
alternate unit system: it reads native outcomes and adds presentation-only
logical values. It does not mutate server combat, creature templates, packets,
or item/spell data.

## Power and Magnitude

```text
mastery_basis = sum(floor(400 * n^1.5), n = 1..mastery_rank)

chaos_power = 1,000
            + fully_attuned_unique_items * 5,000
            + mastery_basis * 25
            + permanent_crucible_investment * 10
```

Power is reconstructed from current durable state; there is no Chaos currency
or lifetime event ledger. The server transports power as a decimal string.
Magnitude is its base-1000 order: 0 Quiet, I Stirring, II Resonant,
III Elevated, IV Ascendant, V Transcendent, and VI+ Unbounded.

The server supplies `chaos_scale = 1000 + min(250, 25 * magnitude)` basis
points. The client interpolates the native-level taper at anchors
`(1,1000), (10,600), (30,300), (50,180), (60,140), (70,120), (80,100)`;
skull targets use level 80. Native final health already contains rank,
template, expansion, difficulty, and server-rate relationships, so Chaos adds
no classification multiplier.

Actual damage, healing, prevention, and health use the displayed/destination
unit's scale. Static equipment and fixed spell/aura/proc references use the
viewer's Personal Chaos Scale because no future recipient exists yet.

## State and protocol

`ap_mastery.chaos_enabled` is authoritative character state. The guarded
upgrade adds `TINYINT(1) NOT NULL DEFAULT 0`; existing characters need no data
rewrite because power is derived at hydration time. `Chaos:ApplyAuthoritativeState`
is the single presentation projection seam. It consumes both an already
hydrated StateStore snapshot and every later authoritative STATE packet,
including unchanged same-character snapshots after logout/relog. Repeated
application is idempotent and restores exact captured CVar/alpha baselines.

Product and expected AddOn version are `2.1.0`. Bridge protocol remains v1:
Chaos adds optional capability/action/state fields without changing framing or
the compatibility handshake. A complete 2.1 server/AddOn pair is required for
Chaos; older peers simply lack the feature contract.

## Presentation ownership

- Stock health: PlayerFrame, TargetFrame, FocusFrame, PetFrame,
  PartyMemberFrame1–4, and vehicle-bound PlayerFrame.
- Combat: Chaos-owned floating outcomes and presentation-only values supplied
  to Blizzard's live Combat Log formatter; wording, localization, hyperlinks,
  and filtering remain Blizzard-owned.
- Tooltips: native Blizzard content, then Echoes Attunement, then Chaos
  augmentation. No `ClearLines`, hyperlink reconstruction, broad regex prose
  rewriting, or per-frame rebuild loop is used.
- UI: the existing Settings region hosts the toggle and the existing
  Progression region hosts Power/Magnitude. No major component moved and no
  navigation destination was added.

See [the illusion-risk audit](CHAOS-ILLUSION-RISK-AUDIT.md) for boundaries and
[the player guide](CHAOS_MODE.md) for the concise contract.
