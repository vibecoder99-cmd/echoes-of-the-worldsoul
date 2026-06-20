# Installation Guide

This guide covers a full fresh installation of Echoes of the Worldsoul on an
AzerothCore 3.3.5a server. Follow the steps in order; each phase depends on the
previous one completing without errors.

---

## Prerequisites

Before starting, confirm you have:

- **AzerothCore 3.3.5a** — source checkout, buildable with CMake. The mod adds
  a C++ module; a binary-only install is not sufficient.
- **Eluna Lua scripting engine** — must be compiled into your AzerothCore build.
  If you are not sure, check for `ELUNA` in your CMake configuration output.
- **MySQL** — access to both `acore_characters` and `acore_world` databases with
  enough privileges to run `CREATE TABLE` and `INSERT`.
- **Python 3.6+** — needed only for the DBC patch step. `python --version` to
  confirm.
- **WoW 3.3.5a client (build 12340, enUS)** — a clean, unmodified copy for the
  client-side steps. The current Battle.net client is not a drop-in replacement.
  Use a legally obtained 3.3.5a client or a personal archival backup. Avoid
  repacks or clients already modified by another server.
- An MPQ editor such as **Ladik's MPQ Editor** (free) for packaging the patched
  DBC into a client patch file.

---

## Step 1 — Apply the C++ Module Patch

The mod ships as a unified diff against an AzerothCore checkout. Apply it from
the root of your AzerothCore source tree:

```bash
git apply path/to/echoes-of-the-worldsoul/cpp_patch/mod_attunement_plus.patch
```

This creates two new files under `modules/mod-attunement-plus/src/`:

```
modules/mod-attunement-plus/src/
    mod_attunement_plus.cpp
    mod_attunement_plus_loader.cpp
```

AzerothCore's build system auto-discovers modules under `modules/*/src/` — no
`CMakeLists.txt` changes are needed.

**Rebuild AzerothCore:**

```bash
cd build
cmake ..          # re-run cmake so it picks up the new module files
make -j$(nproc)   # or your platform equivalent (MSBuild on Windows)
```

Confirm the build output mentions `mod-attunement-plus` being compiled. If it
does not appear, verify the two `.cpp` files are present in the path above.

---

## Step 2 — Apply the SQL Schema

Two SQL files must be run against two different databases. Order matters: run
the schema file first.

**Characters database (20 tables):**

```bash
mysql -u [user] -p acore_characters < sql/schema/full_schema.sql
```

This creates all 20 `ap_*` tables. The statements are `CREATE TABLE IF NOT EXISTS`
and are safe to run on an existing install — they produce no errors and make no
changes to tables that already exist.

**World database (custom items):**

```bash
mysql -u [user] -p acore_world < sql/data/world_items.sql
```

This inserts two rows into `item_template` using `INSERT IGNORE`:

| Entry  | Name                    | Notes                              |
|--------|-------------------------|------------------------------------|
| 900010 | Worldsoul Echo Fragment | Right-click to receive Essence + gold |
| 900011 | Worldsoul Residue       | Stackable currency (max 999)       |

`INSERT IGNORE` is safe to run multiple times — subsequent runs produce no
errors and make no changes if the rows already exist.

---

## Step 3 — Deploy the Lua Scripts

Copy all 20 files from `lua_scripts/` into your server's Eluna script folder.
The default path in an AzerothCore build is:

```
build/bin/RelWithDebInfo/lua_scripts/    (Windows, RelWithDebInfo build)
build/bin/lua_scripts/                   (Linux)
```

The files to copy:

```
ap_commands.lua         ap_rack.lua
ap_core.lua             ap_sinks.lua
ap_events.lua           ap_tests.lua
ap_flash_messages.lua   ap_tooltip.lua
ap_forge.lua            ap_tutorial.lua
ap_gm.lua               ap_ui.lua
ap_gm_aether.lua        ap_visage.lua
ap_items.lua            ap_worldsoul_voice.lua
ap_pvp.lua              ap_zzapi.lua
ap_auralab.lua          zz_eluna_probe.lua
```

`zz_eluna_probe.lua` loads last (alphabetical) and confirms the Eluna
environment is available. If it produces errors on startup, your Eluna build
has a problem unrelated to this mod.

**After copying, start (or restart) the worldserver.** Eluna loads scripts at
startup; there is no hot-reload for the initial load. Once running, individual
scripts can be reloaded in-game with `.reload eluna`.

---

## Step 4 — Patch the Client Item.dbc

The two custom items require a corresponding entry in the client's `Item.dbc`
so the client knows how to render and query them. Without this step, items
900010 and 900011 appear as question marks and generate continuous
`CMSG_ITEM_QUERY_SINGLE` retry loops.

**Clean client requirement:** The patch script was written against a completely
vanilla, unmodified WoW 3.3.5a (build 12340, enUS) `Item.dbc`. If your client
data has been modified by any other custom patch, do not run this step against
that modified file — extract a clean `Item.dbc` from the original MPQ archives
first.

**Run the patch script:**

```bash
python dbc_patch/patch_item_dbc.py  path/to/vanilla/Item.dbc  Item_patched.dbc
```

The script prints a before/after summary and runs eight self-checks. All checks
must show `[PASS]` before the output file is safe to use. If any check shows
`[FAIL]`, do not use the output — check `dbc_patch/DBC_EDITING_NOTES.md` for
what may have gone wrong.

Expected output on a clean 12340 Item.dbc:

```
=== INPUT ===
  Record count : 46,096
  File size    : 1,475,093 bytes

=== OUTPUT ===
  Record count : 46,098  (was 46,096, +2)
  File size    : 1,475,157 bytes  (was 1,475,093, +64)

=== SELF-VERIFICATION ===
  [PASS] Header magic
  [PASS] Header record count  (46,098 == 46,098)
  [PASS] File size matches header  (1,475,157 == 1,475,157)
  [PASS] String block unchanged  (1 bytes)
  [PASS] Entry 900010 bytes match  (record index 46096, offset 1475092)
  [PASS] Entry 900010 is inside record region
  [PASS] Entry 900011 bytes match  (record index 46097, offset 1475124)
  [PASS] Entry 900011 is inside record region
```

**Package into a client patch MPQ:**

Using Ladik's MPQ Editor (or equivalent):

1. Create a new archive. Choose MPQ format version 1 (compatible with 3.3.5a).
2. Add `Item_patched.dbc` to the archive at the internal path `DBFilesClient\Item.dbc`.
3. Save the archive as `patch-Z.mpq` (or any name that sorts after `patch-3.MPQ`
   in your client's `Data\` folder).
4. Copy the finished MPQ to your WoW client's `Data\` folder.

Distribute this MPQ to any players who connect to your server. The `join-the-server/`
folder in this repository is a ready-made player package containing a pre-built
copy of this MPQ (`patch-Z.mpq`) plus the client AddOn.

---

## Step 5 — Install the Client AddOn

Copy the `client_addon/EchoesOfTheWorldsoulBridge/` folder into your WoW client:

```
WoW 3.3.5a.12340\
  Interface\
    AddOns\
      EchoesOfTheWorldsoulBridge\
        EchoesOfTheWorldsoulBridge.lua
        EchoesOfTheWorldsoulBridge.toc
```

The AddOn bridges the server-side Lua system to the client UI: it renders
attunement progress in item tooltips, drives the `#ap` panel, and shows the
minimap button.

Enable it at the character select screen under **AddOns**. If it appears greyed
out or flagged as out-of-date, enable **Load out of date AddOns**.

---

## Smoke Test Checklist

After completing all five steps, run through these checks before opening the
server to players:

- [ ] Worldserver starts with no Eluna script errors in the log
- [ ] Log in with a test character
- [ ] Type `#ap` — the Echoes of the Worldsoul panel opens
- [ ] Type `#ap help` — the command list appears in chat
- [ ] Kill any mob — attunement progress message appears for at least one equipped item
- [ ] Kill a boss — verify boss bonus Essence fires (check `#ap` Essence balance)
- [ ] Use a GM account to give yourself item 900010 (`#additem 900010`) — it
  appears with a name and icon, not a question mark
- [ ] Use a GM account to give yourself item 900011 (`#additem 900011`) — same
- [ ] Right-click item 900010 — it activates (spell 8690 fires, item consumed)
- [ ] Type `#ap forge` — the Legacy Forge panel opens (requires a fully-attuned item to test dissolution)
- [ ] Type `#ap rack` — the Attunement Rack panel opens
- [ ] Type `#ap crucible` — the Crucible sink panel opens
- [ ] Log out and back in — Essence balance and attunement progress are preserved

### Regression Tests (GM only)

Run from a GM account in-game:

```
#aptest tier4
#aptest tier5
#aptest threat
#aptest tier6
```

All tests should report PASS. If any test fails, check the worldserver
console log for details before opening the server to players.

If all checks pass, the installation is complete.

---

## Updating an Existing Install

### SQL migrations

Schema changes between releases ship as numbered migration files in
`sql/migrations/`. When updating, run any migration files numbered higher than
what you have already applied, in order:

```bash
# Example: updating from 1.0.0 to a release that added migration 002
mysql -u [user] -p acore_characters < sql/migrations/002_example_feature.sql
```

Each migration file is idempotent — running it twice produces no errors and no
duplicate changes. Running an old migration by accident is harmless.

Migration `001_initial_release.sql` is the 1.0.0 baseline marker; it contains
no SQL to execute (see its header comment). For a fresh install, always use
`sql/schema/full_schema.sql` rather than applying migrations one by one.

> **Why no migration-tracking table?** At this project's current scale — one
> primary operator plus anyone pulling a GitHub release — idempotent files
> applied by visual inspection of the `migrations/` folder is sufficient. A
> formal migration runner would add complexity without meaningful benefit here.
> If this ever changes, a tracking table can be added as migration 00N.

### Lua scripts

Copy the updated `.lua` files from `lua_scripts/` into the server's Eluna
scripts folder and run `.reload eluna` in-game, or restart the worldserver.

### AddOn (client)

Replace the `EchoesOfTheWorldsoulBridge/` folder in `Interface/AddOns/` with the
updated version. If the `## Version` field in `EchoesOfTheWorldsoulBridge.toc`
changes, the server's in-game version mismatch warning will fire for any player
still on the old version — this is the intended signal for players to update.

### C++ module

Re-apply the updated patch from `cpp_patch/`, rebuild AzerothCore, and restart
the worldserver.

### DBC / client data

Re-run `dbc_patch/patch_item_dbc.py` against a clean base `Item.dbc`,
repackage the MPQ, and distribute the updated `patch-Z.mpq` to players (or
update the `join-the-server/` package).
