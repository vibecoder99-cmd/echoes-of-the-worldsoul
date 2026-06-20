# Echoes of the Worldsoul

An item attunement and progression mod for AzerothCore 3.3.5a. Every piece of
gear you carry has a history. Fight with it, and the Worldsoul begins to
remember — unlocking passive bonuses, currency, and cosmetic effects that
deepen the longer you stay.

---

## What It Does

**Item Attunement** tracks per-item progress through combat kills. Once an item
reaches full attunement it is permanently marked and begins generating benefits.
Attunement is per-account and survives item transfers between your characters.

**Essence** is the primary currency, earned through kills, boss encounters,
quests, PvP, and item attunement milestones. Essence persists between sessions.

**Mastery** ranks up as you invest Essence. Higher mastery unlocks deeper
Crucible capacity and increases passive gain rates.

**The Crucible** is a set of 18 investment categories — Life Leech, Spell
Mitigation, Spell Reflection, XP Rate, item drop bonuses, and more. Essence
spent in the Crucible is permanent and shared across your account.

**The Legacy Forge** lets you dissolve fully-attuned items you no longer need,
converting them into Worldsoul Residue and a burst of Essence. Each item can be
dissolved once per account.

**The Attunement Rack** holds up to 9 items and attunes them passively through
your combat kills, without those items needing to be equipped or even in your
bags. Expand rack capacity by spending Worldsoul Residue.

**Resonant Drops** reward bonus Essence when the same item drops for you
repeatedly — a Legacy Surge activates on the fourth and later duplicate drops.

**Visage** applies cosmetic aura and flash effects on kill, with selectable
themes and intensity tiers that reflect your Worldsoul alignment.

**World Threat** is a voluntary challenge system. Set your threat level from
Peaceful to Ascendant — higher threat increases reward potential through a
momentum streak system, but death resets your momentum, costs Essence, weakens
unfinished attunement progress, and applies an XP debt. No artificial stat
inflation — the pressure comes from real consequences for recklessness.

**The Worldsoul Voice** delivers escalating flavor messages as you engage with
the system — quiet at first, more present as your attunement deepens.

---

## Requirements

| Component | Version / Notes |
|-----------|----------------|
| AzerothCore | 3.3.5a (any recent release) |
| Eluna Lua engine | Must be enabled in your AzerothCore build |
| MySQL | acore_characters and acore_world databases |
| WoW client | 3.3.5a, build 12340 (enUS) — vanilla, unmodified |
| Python | 3.6+ (only needed to run the DBC patch script) |

---

## Quick Start

See **`INSTALL.md`** for the full step-by-step setup. The short version:

1. Apply the C++ patch from `cpp_patch/` and rebuild AzerothCore.
2. Run `sql/schema/full_schema.sql` against `acore_characters`.
3. Run `sql/data/world_items.sql` against `acore_world`.
4. Copy all files from `lua_scripts/` into your server's `lua_scripts/` folder.
5. Patch your `Item.dbc` using `dbc_patch/patch_item_dbc.py` and put the result
   in a client patch MPQ.
6. Install `client_addon/EchoesOfTheWorldsoulBridge/` into your WoW client's
   `Interface/AddOns/` folder.
7. Restart the server. Type `#ap` in-game to confirm the mod is live.

---

## Configuration

All runtime configuration lives in `ap_core.lua` under the `AP.Config` table.
Key settings:

| Key | Default | Description |
|-----|---------|-------------|
| `perKillBase` | `(set in config)` | Base attunement progress per kill |
| `bonusBoss` | `(set in config)` | Bonus attunement for boss kills |
| `capPerItem` | `(set in config)` | Maximum attunement progress per item |
| `essencePerKill` | `(set in config)` | Base Essence awarded per kill |
| `masteryThresholds` | array | Essence thresholds for each Mastery rank |

Crucible sink caps, Rack slot costs, Forge dissolution rewards, and Visage
theme definitions are all configurable in their respective `ap_*.lua` files.
No database changes are needed to adjust rates — edit the Lua and `/reload`
the scripts.

---

## Project Structure

```
echoes-of-the-worldsoul/
├── lua_scripts/          Server-side Eluna Lua scripts (18 files)
├── cpp_patch/            Unified diff for the C++ AzerothCore module
├── sql/
│   ├── schema/           full_schema.sql — all 20 ap_* tables (acore_characters)
│   └── data/             world_items.sql — custom item rows (acore_world)
├── dbc_patch/            patch_item_dbc.py + DBC_EDITING_NOTES.md
├── client_addon/         EchoesOfTheWorldsoulBridge WoW AddOn
├── INSTALL.md
├── CHANGELOG.md
├── LICENSE
└── README.md
```

---

## Compatibility

**Tested on:**
- AzerothCore WotLK 3.3.5a with mod-eluna enabled
- Windows local server environment (RelWithDebInfo build)
- MariaDB/MySQL character database
- C++ module compiled into worldserver.exe
- Lua 5.2 runtime via Eluna

**Compatibility warning:** Echoes of the Worldsoul depends on specific
AzerothCore + Eluna behavior. Other Eluna builds may use different event IDs,
gossip signatures, or available APIs. Run the included tests and compatibility
probe (`zz_eluna_probe.lua`) before assuming support.

**Known unsupported Eluna APIs** (workarounds used):
`RegisterCommand`, `Player:SetStat`, `Player:IsQuestRewarded`, `HasAura`,
`GetBagSize`, `GetFloat`, `Player:GetGMLevel`

**SQL requirement:** Run SQL migrations before enabling Lua scripts. Some
AzerothCore builds hard-abort on missing columns/tables during DB queries.

**C++ module:** Required for stat application. Must be compiled into
`worldserver.exe` via AzerothCore module system. No separate DLL.

---

## Extension API

Echoes of the Worldsoul exposes `AP.API` for future dependent modules
(Empire, Prestige, Companions, Fusion Forge, etc.). See `docs/API.md` and
`docs/EXTENSIONS.md` for the full reference.

Extensions register via `AP.API.RegisterExtension()` and subscribe to game
events via `AP.API.RegisterHook()`. Hook dispatch is pcall-safe — one
extension error cannot crash the base module.

---

## Testing

In-game (GM only): `#aptest` runs all regression suites.

Individual suites: `#aptest tier4`, `#aptest tier5`, `#aptest threat`,
`#aptest tier6`

Full suite count: 18 test suites, 150+ individual tests.

---

## Acknowledgments

Inspired by the attunement concept present in **Synastria** private server
progression systems. This implementation is independent — written from scratch
for AzerothCore with its own design, database schema, Lua architecture, and
feature set.

Developed with the assistance of **Claude** (Anthropic) as an AI pair
programmer.

Special thanks to **Pramm**, Level 80 Orc Warrior, who endured every crash,
exploit, and item-loss incident this project produced and is still standing —
and to the many short-lived Orc Warrior clones created, tested, and deleted in
his shadow, whose sacrifices were no less essential and whose names history does
not record.

---

## License

Copyright (C) 2025-2026 vibecoder99.  
Licensed under the GNU General Public License v3.0 or later. See `LICENSE`.
