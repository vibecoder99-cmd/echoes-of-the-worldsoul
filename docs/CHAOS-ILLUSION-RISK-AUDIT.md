# Chaos Mode illusion-risk release audit

Audit date: 2026-08-31. Scope: stock/default 3.3.5a presentation and Echoes-owned UI. Native mechanics and server values are unchanged.

## Classification inventory

| Surface | Finding | Class | Disposition |
|---|---|---:|---|
| Player/target numeric health | Direct health outcome | P0 | Covered by reversible Chaos overlays |
| Focus, pet, party numeric health | Stock `TextStatusBarText` can expose native HP | P1 | Covered when the corresponding native text is visible; native visibility policy is preserved |
| Player/pet hit indicators | `UNIT_COMBAT` feedback bypasses floating-combat-text CVars | P0 | Native numeric font strings suppressed while Chaos is on; existing Chaos combat output remains authoritative |
| Vehicle PlayerFrame | Stock frame rebinds from `player` to `vehicle` | P1 | Overlay now follows the frame's actual unit token |
| Raid/compact raid frames | No stable 3.3.5a ordinary numeric-HP contract certified | P2 | Bars/percentages remain native; no raid redesign |
| Focus-target/target-target | Small stock bars; numeric visibility not live-certified | P2 | Deferred |
| Spell/action/pet/talent/macro spell tooltips | Localized rendered prose may contain direct damage, healing, absorb, or periodic values; future recipient is unknown | P1 | Documented boundary; no dishonest target multiplier and no regex prose engine |
| Buff/debuff tooltips | Percentages are safe; fixed periodic/heal/absorb prose can expose native coefficients | P1 | Documented boundary pending a structured narrow data source |
| Proc/enchant/use/consumable tooltips | Item prose can contain direct native coefficients; recipient is unknown | P1/P2 | Weapon base range alone has an honest personal-reference translation; other prose deferred |
| Paperdoll | Health and weapon range are Chaos-presented; identity stats, armor, AP/SP, ratings, resources, and percentages stay native | GREEN | Intended law |
| Floating combat and live Combat Log | Destination-scale damage/healing/prevention/environmental outcomes | GREEN | Covered |
| Historical Combat Log refilter | Blizzard may reformat stored events through an internal path that bypasses the live wrapper | P2 | Requires live filter/reopen certification; no subsystem rewrite |
| Item links | Shared deterministic item seam | GREEN | Covered; hyperlink data unchanged |
| Spell links | Same rendered spell-prose limitation as action/spellbook tooltips | P1 | Deferred |
| Inspect | Viewer-side weapon reference is acceptable; remote identity stats remain native | GREEN/P2 | No implication that the inspected player enabled Chaos |
| Environmental/death UI | CLEU floating/log environmental damage covered; separate death recap/script text not certified | P2 | Deferred live certification |
| Vehicles | PlayerFrame health fixed; vehicle ability prose remains spell-tooltip boundary | P1/P2 | Partial closure |
| Pets/guardians/playerbots | Pet health and feedback covered; outcomes use destination scale; bot-specific status UI not owned by Echoes | GREEN/P2 | No AI/mechanics changes |
| Quest/scripted encounter text | Rare authored numeric prose can expose native values | P2 | Document; never rewrite quest mechanics |
| Echoes screens | Attunement, Mastery, Crucible, Talents, Rack, Forge, retained stats, Essence/Aether/Residue are identity/progression inputs | GREEN | Remain native by design |
| Third-party addons | May read native APIs/CLEU and display engine-native values | P2 | Explicit V1 compatibility boundary |
| GM/debug/admin output | Administrative truth intentionally remains native | P2 | Explicit non-player-presentation boundary |

## Translation math

- Unit health: `displayed = native health × Chaos:GetScale(displayedUnit)` for both current and maximum health.
- Combat outcomes: `displayed = effective native outcome × Chaos:GetScale(destinationUnit)`.
- Static weapon reference: `displayed base range/DPS = native range/DPS × Chaos:GetPersonalScale()` and is labeled as a reference, not a promised final hit.
- Percentages, resources, currencies, ratings, armor, AP/SP, primary attributes, mana/rage/energy/runic power, and item level are not translated.

## Lifecycle and restoration

- Item tooltip order is native, then Attunement, then registered Chaos augmentation; per-tooltip lifecycle state prevents duplicates.
- Auxiliary unit-frame overlays appear only when stock numeric text is itself visible, preserving the player's status-text preference.
- Chaos off restores each captured native alpha exactly and hides every Chaos overlay.
- No `ClearLines`/`SetHyperlink` rebuild loop, server mutation, combat mutation, spell-data edit, or item-data edit is used.

## Release gate

Automated coverage passes. Live certification remains required for spell/aura examples, party/focus/pet frames, vehicle mode, historical Combat Log refiltering, inspect/spell links, and environmental/death presentation because the client was not running at audit close.

User validation now covers persisted-ON relog, character switching, Mage and
Warlock spell behavior, floating output, live Combat Log values, broad NPC
samples, Magnitude I believability, and stable tooltip behavior. Supported
fixed spell/aura/proc references are implemented through the bounded Personal
Chaos seam; unsupported dynamic/localized prose remains native by design.

Current verdict: **GREEN** for the defined 2.1.0 scope. No P0 or P1 defect is
open; third-party, raid/focus-target, GM/debug, environmental/death, and
historical-refilter boundaries remain P2.
