# Changelog

Feature evolution by milestone. This is not a commit log — each entry describes
what a phase introduced and why, not every individual change made during it.

**1.0.0 is the first formally versioned release.** All entries from this point
forward are headed by their version number (e.g. `## 1.1.0 — Feature Name`),
following semantic versioning: PATCH for bug fixes and balance changes, MINOR
for new features and backward-compatible additions, MAJOR for breaking schema
changes or removed features. The nine historical milestone entries below predate
formal versioning and are kept as-is for context.

---

## 1.6.0 — Tier 6: Public API & Extension Readiness

- Added `AP.API` namespace with 17 stable read-only functions for querying player progression
- Added extension registry (`AP.API.RegisterExtension`, `AP.API.GetExtensions`)
- Added hook system (`AP.API.RegisterHook`, `AP.API.DispatchHook`) with pcall-safe dispatch
- 8 defined hook points: OnItemAttuned, OnThreatChanged, OnThreatDeathPenalty, OnForgeDissolve, OnVisageChanged, and more
- Hook dispatch integrated at stable points in kill handler, death handler, forge, visage, and threat UI
- Added `docs/API.md` and `docs/EXTENSIONS.md` for future module authors
- 15 Tier 6 regression tests covering API safety, extension registration, hook dispatch, and error isolation
- All disabled future modules verified hidden from player UI

## 1.5.0 — World Threat v2/v2.1/v2.2

- Replaced flat threat slider with momentum-based challenge system
- Threat Level 0-10 with named tiers (Peaceful through Ascendant)
- Momentum builds from level-appropriate kills, resets on death
- Content cap system: normal mobs cap at +40%, elites +70%, bosses +85%, raids +100%
- Fair death penalties: attunement progress loss, Essence tax (capped), XP debt (action-recoverable)
- No timers — all penalties recovered through gameplay
- Safety scalar reduces Life Leech and Res Resilience at higher threat
- Anti-cheese dampener tightens at higher threat
- Threat persists through relog (DB-backed)
- Dedicated World Threat UI page with honest mechanics display
- 36+ threat regression tests

## 1.4.0 — Tier 5: Polish & Stability

- Replaced "Mastery & Essence" with unified Progression Status page
- Per-system next-goal guidance (Mastery, Echoes, Rack, Visage)
- Standardized labels: Effective Absorption, Base Absorption, Level Scalar, Worldsoul Residue
- All player-facing prefixes unified to `[Worldsoul]`
- Debug prints gated behind `AP.Config.Debug`
- GM-locked: testaura, clearaura, aurastatus, Aura Lab
- Added `AP.IsGM()` compatibility-safe GM wrapper
- 10 Tier 5 regression tests

## 1.3.0 — Tier 4: Visage Aura System

- Complete 5-theme x 5-tier cosmetic aura system with 25 verified spell IDs
- Player-selectable intensity tier (T1 Subtle through T5 Dramatic)
- Primary and secondary aura selections independent and persistent
- Aura Lab for safe spell testing (GM-locked)
- Aura apply path unified for toggle, menu, and login refresh
- 10 Tier 4 regression tests

## 1.2.0 — Tier 3: Bug Fixes & Stability

- Fixed Forge sync bug (rack-attuned items visible without relog)
- Fixed gear-cycling feedback formula
- Fixed Rack XP balance (split across entries, independent of equipped)
- Replaced crash recovery heuristic with `ap_session_state` clean_exit model
- Forge filters consumables, UTF-8 BOM/smart-quote corruption fixed
- 7 Tier 3 regression tests

## 1.1.0 — Tier 2: LevelAbsorbScalar Fix

- C++ LevelAbsorbScalar now matches Lua: level 1-9 = 0%, level 10+ linear, level 80 = 100%
- Build-timestamp logging for binary verification
- Regression tests passing

---

## Lore Consistency Pass

Final pre-release sweep to bring all player-facing text into alignment with the
Worldsoul voice established during the Voice milestone.

- All remaining `[AP]` and `Attunement Plus` player-facing strings replaced
  across server Lua, C++, and the client AddOn
- C++ combat proc notifications (`[AP]` tag, generic phrasing) rewritten to
  `|cff9966ff[Worldsoul]|r` voice with flavor language matching the system tone
- Stale `customMsg` overrides removed from `AP.Tutorial.Trigger` call sites in
  `ap_forge.lua` and `ap_rack.lua` — triggers now resolve through the canonical
  `AP.Tutorial.Messages` table instead of bypassing it
- Forge item list and Catalyst button labels standardised to newline-separated
  format; Rack ShowPage header and `[Remove]` label retained for UI clarity
- AddOn `.toc` title and notes updated to Echoes of the Worldsoul branding
- Copyright headers added to all source files

---

## Worldsoul Voice

Introduced the escalating flavor message system that gives the Worldsoul a
persistent presence across all player interactions with the mod.

- `AP.Voice.Speak(player, triggerKey)` — session-scoped message escalation,
  counter keyed per player GUID and trigger key, not persisted to the database
- Distinct message tiers per trigger (quiet acknowledgment → active presence →
  deeper recognition) that advance as the player engages with the same system
  repeatedly in a session
- Voice lines added across attunement progress, Essence gains, Crucible
  investment, Forge dissolution, and Rack interactions
- `ap_worldsoul_voice.lua` introduced as a standalone module

---

## PvP

Extended Essence rewards to cover player-versus-player combat.

- Essence awarded on PvP kills, scaled by target level relative to the attacker
- Battleground objective reward framework added (`ap_bg_objectives` table) for
  future expansion; Eluna BG objective hooks are not available in the 3.3.5a
  build this mod targets, so the framework is defined but unpopulated
- Diminishing returns logic prevents farming low-level or same-character targets
- `ap_pvp.lua` introduced as a standalone module

---

## Security Hardening

Addressed several exploitable paths identified after the core feature set was
stable.

- Rate-limit throttle added to all three C++ combat proc notification functions
  (Life Leech, Spell Mitigation, Spell Reflection) — repeated rapid procs now
  suppress notifications rather than spamming chat, while the underlying proc
  still fires
- Input validation tightened on Forge dissolution: pending-guard check prevents
  duplicate dissolution events if the player submits the action twice before the
  async DB write completes
- Rack add/remove operations validate slot bounds and item possession at the
  point of action, not only at panel open time
- GM-only commands separated into `ap_gm.lua` and `ap_gm_aether.lua`; all GM
  paths require the caller's security level to be checked before execution

---

## Legacy Forge and Attunement Rack

The two largest feature additions after the initial core, shipped together as
the item economy phase.

**Legacy Forge:**
- Players can dissolve fully-attuned items they no longer need, receiving
  Worldsoul Residue and a burst of Essence in return
- Each item can be dissolved once per account; the `ap_dissolved_items` table
  enforces this permanently
- Worldsoul Residue ledger tracked in `ap_residue` (per account); physical item
  counts reconciled against the ledger on login
- Crucible Catalyst added: spend 10 Residue for 5,000 Essence (accessible from
  the Forge panel)
- Custom items introduced: 900010 (Worldsoul Echo Fragment) and 900011
  (Worldsoul Residue) — required corresponding `Item.dbc` and `item_template`
  entries

**Attunement Rack:**
- Players can place up to 3 items (expandable to 9) in the Rack; those items
  receive passive attunement ticks from the player's combat kills without
  needing to be equipped
- Rack slot capacity expanded by spending Worldsoul Residue
- `ap_rack` table tracks slot contents per character

**Resonant Drops:**
- When the same item drops for a player for the fourth time or more, a Legacy
  Surge activates: 3× Essence bonus on that drop event
- `ap_resonant_drops` tracks per-account drop counts per item entry

---

## Visage

Added the cosmetic layer: kill aura effects and flash animations that reflect
the player's Worldsoul alignment.

- Selectable primary and secondary Visage themes (e.g., `worldsoul`)
- Aura effect on kill, flash effect on attunement milestone
- Per-character settings (theme, aura toggle, flash toggle, chat flavor toggle)
  persisted in `ap_visage`
- `#ap visage` panel for in-game theme selection
- `ap_visage.lua` introduced as a standalone module

---

## The Crucible

Introduced the permanent Essence investment system, giving long-term progression
depth beyond Mastery ranks.

- 18 sink categories spanning combat passives (Life Leech, Spell Mitigation,
  Spell Reflection, Armor Penetration, Execute Power), economy modifiers (XP
  Rate, Aether Rate, Boss Rate, drop bonuses), and utility effects
- Investment is per-account and permanent — Essence spent in the Crucible is
  not refundable
- Sink caps scale with Mastery rank, gating deeper investment behind progression
- `ap_aether_sinks` tracks per-account investment per category
- `ap_sinks.lua` introduced; C++ module extended with three combat proc hooks
  (leech, mitigation, reflection) to read live sink values and apply effects
- `#ap crucible` panel for browsing and investing in sink categories

---

## Rebrand

Renamed the project from **Attunement Plus** to **Echoes of the Worldsoul**
before the majority of the feature set was built, establishing the identity the
rest of the system would be written against.

- Project name, color scheme, and tag prefix changed throughout
  (`[AP]` / `00ff99` / `88aaff` → `[EotW]` / `[Worldsoul]` / `9966ff`)
- `AP` retained as the internal Lua namespace (all tables remain `AP.*`)
- `#ap` retained as the player command prefix for familiarity and brevity
- AddOn `.toc` title updated; folder and file names deferred (technical rename
  would break live installs mid-development)

---

## Initial Core

The foundational attunement and Essence system that everything else is built on.

- Per-item attunement progress tracked through combat kills
  (`ap_item_attune` table); progress is permanent once set and survives item
  transfers between characters on the same account
- Stat snapshot captured at full attunement (`ap_item_snapshot`): raw stats
  of the item at the moment it was claimed, used by passive bonus calculations
- Essence currency earned on kills, with base rate and boss bonus configurable
  in `ap_core.lua`; balance persisted in `ap_mastery`
- Mastery rank system: ranks up as cumulative Essence investment passes
  configured thresholds; higher rank unlocks higher sink caps
- Tutorial system: one-time milestone messages fired per account for first
  attunement, first Essence gain, first Mastery rank, and other key moments
  (`ap_aether_milestones` table)
- `AP.Config` table in `ap_core.lua` as the single configuration entry point
  for all rates and thresholds
- `#ap` command opens the main panel; `#ap help` lists all subcommands
- Eluna combat event hooks in `ap_events.lua`; C++ module (`mod_attunement_plus`)
  handles combat proc effects that require engine-level access
