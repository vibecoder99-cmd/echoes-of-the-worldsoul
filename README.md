# Echoes of the Worldsoul

An item attunement and progression mod for AzerothCore 3.3.5a. Every piece of
gear you carry has a history. Fight with it, and the Worldsoul begins to
remember — unlocking passive bonuses, currency, and cosmetic effects that
deepen the longer you stay.

---

## Feedback / Compatibility Reports

Echoes of the Worldsoul is under active development toward a 2.0 release.
This package now includes a graphical Client Companion AddOn and optional
Playerbots integration in addition to everything `v1.6.0-rc1` shipped;
compatibility verification for this expanded scope is still in progress.

Compatibility reports and balance feedback are welcome through
[GitHub Issues](https://github.com/vibecoder99-cmd/echoes-of-the-worldsoul/issues/new/choose).
Please include your AzerothCore revision, Eluna version, operating system, SQL
import result, Lua load result, C++ rebuild result, and client-pack status when
reporting issues.

---

## What It Does

**Item Attunement** tracks per-item progress through combat kills. Once an item
reaches full attunement it is permanently marked and begins generating benefits.
Attunement is per-account and survives item transfers between your characters.

**Essence** is the primary currency, earned through kills, boss encounters,
quests, PvP, and item attunement milestones. Essence persists between sessions.

**Mastery** ranks up as you invest Essence. Higher Mastery increases your
effective absorption percentage, deepening the stat power you retain from
attuned gear.

**The Crucible** is a set of 18 investment categories — Life Leech, Spell
Mitigation, Spell Reflection, XP Rate, item drop bonuses, and more. Essence
spent in the Crucible is permanent and shared across your account.

**The Legacy Forge** lets you dissolve fully-attuned items you no longer need,
converting them into Worldsoul Residue and a burst of Essence. Each item can be
dissolved once per account.

**The Attunement Rack** starts with 3 slots and can be expanded up to 20,
allowing stored items to attune passively through your combat kills without
needing to be equipped. Expand rack capacity by spending Worldsoul Residue.

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
| mod-ale (Eluna fork) | External prerequisite -- not bundled in this repository. Build with `LUA_VERSION=lua52` (this project's Lua targets Lua 5.2, not the more common 5.1). See `modules/mod-ale` on your own AzerothCore checkout, or your server's existing Eluna install. |
| mod-playerbots | Optional external prerequisite. Only needed if you want Playerbots integration (`cpp_patch/mod-echoes-playerbots/`); everything else in this package works with zero Playerbots dependency. |
| MySQL | acore_characters and acore_world databases |
| WoW client | 3.3.5a, build 12340 (enUS). Players need the provided client patch MPQ and EchoesOfTheWorldsoulBridge addon for custom item display and tooltip support. |
| Python | 3.6+ (to run the DBC patch script and the optional MPQ packaging tool, `dbc_patch/mpq_writer.py`) |

---

## Getting a Clean Wrath 3.3.5a Client

Echoes of the Worldsoul expects a clean World of Warcraft Wrath of the Lich King
3.3.5a client, build 12340.

The current official Battle.net client is not a drop-in replacement for old 3.3.5a
private-server clients. Use a legally obtained clean 3.3.5a client folder or a
personal archival backup of one.

Recommended practices:

- Start from a clean 3.3.5a client, build 12340.
- Avoid repacks, "HD clients," custom launchers, or clients already modified by
  another server.
- Keep one untouched backup copy of the client.
- Make a separate copy for Echoes of the Worldsoul.
- Install only the server-provided `patch-E.MPQ` into `Data/`.
- Install only `EchoesOfTheWorldsoulBridge` into `Interface/AddOns/`.
- If you already have extra `patch-*.mpq` files from another server, remove them
  or use a fresh client copy before testing.

---

## Quick Start

**Recommended: use the installer.** `installer/bin/echoes.sh` (Linux/WSL) or
`installer/bin/echoes.ps1` (Windows) automates every step below -- module
copy, SQL, Lua deployment, patch-E.MPQ build, and client packaging -- and
tracks what it installed in a manifest so `verify`/`upgrade`/`repair`/
`uninstall` work later. See `installer/README.md` for the full command
reference. Typical fresh install:

```bash
installer/bin/echoes.sh install \
  --azerothcore-root /path/to/your/azerothcore \
  --mysql-user <user> --mysql-password <password> \
  --characters-database acore_characters --world-database acore_world \
  --client-root "/path/to/WoW 3.3.5a.12340"
```

Add `--with-playerbots --confirm-playerbots-compatible` only if you run
mod-playerbots and have verified compatibility yourself.

See **`INSTALL.md`** for the full walkthrough, including the manual
step-by-step process for anyone who prefers not to use the installer. The
manual short version:

1. Copy `cpp_patch/mod-echoes-stats/` (required) and, if you run Playerbots,
   `cpp_patch/mod-echoes-playerbots/` (optional) into your AzerothCore
   `modules/` directory and rebuild. `mod-echoes-playerbots` builds safely
   either way -- it self-gates via `#ifdef MOD_PLAYERBOTS`.
2. Run `sql/schema/00_preflight.sql` through `sql/schema/90_validation.sql`,
   in that numeric order, against `acore_characters`.
3. Run `sql/data/world_items.sql` against `acore_world`.
4. Copy all files from `lua_scripts/` into your server's `lua_scripts/` folder.
5. Patch your `Item.dbc` using `dbc_patch/patch_item_dbc.py` (or the combined
   `dbc_patch/build_patch_mpq.py`, which also packages the result into an
   MPQ) and put the result in a client patch MPQ, named `patch-E.MPQ`.
6. Install `client_addon/EchoesOfTheWorldsoulBridge/` into your WoW client's
   `Interface/AddOns/` folder.
7. Restart the server. Type `#ap` in-game to confirm the mod is live.

> **Note:** The public source package does not include MPQ files. Server owners
> should generate or distribute their own client pack. Players joining a server
> running Echoes of the Worldsoul need the server-provided client patch MPQ and
> the EchoesOfTheWorldsoulBridge addon for custom item display and tooltip
> support.

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
├── lua_scripts/          Server-side Eluna Lua scripts (28 files)
├── cpp_patch/
│   ├── mod-echoes-stats/       Required -- engine-level stat/Crucible-effect application
│   └── mod-echoes-playerbots/  Optional -- Playerbots integration, self-gated at compile time
├── sql/
│   ├── schema/           00_preflight.sql .. 90_validation.sql — numbered install package,
│   │                     18 ap_* tables (acore_characters), run in order
│   └── data/             world_items.sql — custom item rows (acore_world)
├── dbc_patch/            patch_item_dbc.py, mpq_writer.py, build_patch_mpq.py,
│                         test_mpq_writer.py, DBC_EDITING_NOTES.md
├── client_addon/         EchoesOfTheWorldsoulBridge WoW AddOn (graphical UI)
├── INSTALL.md
├── CHANGELOG.md
├── LICENSE
└── README.md
```

Not included in this repository: `mod-ale` (the Eluna Lua engine fork this
project's Lua depends on) and `mod-playerbots` (needed only for the optional
Playerbots integration). Both are external prerequisites -- see Requirements
above.

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

**C++ modules:** `mod-echoes-stats` is required for stat/Crucible-effect
application -- must be compiled into `worldserver.exe` via AzerothCore's
module system. No separate DLL. `mod-echoes-playerbots` is optional
(Playerbots integration only) and builds safely whether or not
mod-playerbots is present.

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
