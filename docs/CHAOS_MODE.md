# Chaos Mode

Chaos Mode is an optional, character-scoped presentation system in Echoes
2.1.0. It expresses supported combat values at a larger logical scale while
preserving native Wrath combat and relative power relationships.

Enable **Chaos Numbers** in Client Companion Settings. Progression then shows
your Chaos Power, Magnitude, and rank name. Supported Player, Target, Focus,
Pet, Party 1–4, and vehicle-bound PlayerFrame health-number surfaces display
Chaos health; floating combat outcomes and the live Blizzard Combat Log use
the same destination-based scale. Weapon tooltips and supported fixed
spell/aura/proc values show labeled personal references.

Chaos does not change creature templates, native health, damage resolution,
packets, stats, resources, or encounter mechanics. It preserves Azeroth's
ordinary hierarchy: lower-level content generally becomes easier, normal mobs
remain weaker than elites, and dungeon bosses remain weaker than raid bosses.
The goal is relevance, not equal time-to-kill. **Getting stronger must not make
Azeroth less worth playing.**

The following remain native: Strength, Agility, Stamina, Intellect, Spirit,
Attack Power, Spell Power, armor, ratings, percentages, mana, rage, energy,
runic power, gold, XP, Essence, Aether, Residue, item level, and durability.
World Threat is a separate risk/reward system and does not contribute to Chaos
Power.

Turning Chaos off restores the captured stock presentation. The server owns
the persisted `chaos_enabled` state, so login, reload, relog, and character
switches project from authoritative character state rather than relying on a
manual toggle.

## Boundaries

Third-party AddOns that read native APIs or combat-log events may still show
engine-native values unless specifically integrated. Unsupported dynamic or
localization-ambiguous tooltip prose remains native. GM/debug/admin output is
intentionally native. Raid and focus-target numeric surfaces are not certified
as part of the 2.1.0 stock-frame contract. A historical manual Combat Log
refilter/reopen path remains a P2 presentation boundary; live formatting is
covered.

For implementation details, see [Chaos architecture](CHAOS_ARCHITECTURE.md).
