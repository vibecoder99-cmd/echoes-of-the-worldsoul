# Echoes of the Worldsoul v1.6.0-rc1 — Release Notes

**Release Candidate** — Feature-complete and tested on the documented stack.
Public users with different AzerothCore/Eluna/MySQL setups should run the
included test suites before deploying to production.

---

## What Is This?

Echoes of the Worldsoul is a long-term solo progression module for AzerothCore
WotLK 3.3.5a. Gear attunes through play, permanently contributing power
through stat absorption, mastery, progression sinks, challenge scaling,
cosmetics, and extension APIs for future dependent modules.

## Included Systems

- Gear attunement and permanent stat absorption
- Mastery progression with Essence currency
- Attunement Rack (passive off-hand attunement)
- Legacy Forge and Worldsoul Residue
- Crucible investments (18 categories)
- World Threat challenge mode (momentum-based, fair death penalties)
- Visage cosmetic auras (5 themes x 5 intensity tiers)
- Echo Fragments (duplicate loot → Essence)
- Tutorial and Codex guidance
- Public API and extension hook system

## Not Included (Future Modules)

Empire, Prestige, Fusion Forge, Relics, Companions, Horde Slayer, and
Diplomacy are separate dependent modules planned for future releases.

## Tested Stack

- AzerothCore WotLK 3.3.5a with mod-eluna
- Windows local server (RelWithDebInfo build)
- MySQL/MariaDB
- C++ module compiled into worldserver.exe

Other AzerothCore/Eluna builds may require adjustment.

## Install Order

1. Apply C++ patch and rebuild worldserver
2. Run SQL: `full_schema.sql` against `acore_characters`
3. Run SQL: `world_items.sql` against `acore_world`
4. Copy Lua scripts to server's `lua_scripts/` folder
5. Patch client `Item.dbc` and package as MPQ
6. Install client AddOn
7. Restart worldserver
8. Verify with `#ap` and `#aptest`

See `INSTALL.md` for detailed step-by-step instructions.

## Important Warnings

- **Run SQL before enabling Lua scripts.** Some AzerothCore builds crash on
  missing tables/columns during DB queries.
- **C++ module rebuild required.** The mod statically links into worldserver.exe.
- **No binaries or proprietary files included.** This release contains only
  source code, SQL, documentation, and the client addon.
- **GM tools are access-controlled.** All debug/admin commands require GM status.

## Version History

See `CHANGELOG.md` for the full evolution from Tier 2 through Tier 7.

## License

GNU General Public License v3.0. Copyright 2025-2026 vibecoder99.
