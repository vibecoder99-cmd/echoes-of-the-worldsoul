# Installation Guide

This guide covers a full fresh installation of Echoes of the Worldsoul on an
AzerothCore 3.3.5a server. Follow the steps in order; each phase depends on the
previous one completing without errors.

---

## Recommended: Use the Installer

`installer/bin/echoes.sh` (Linux/WSL) and `installer/bin/echoes.ps1` (Windows)
automate every server-side step in this guide (module copy, SQL, Lua
deployment, patch-E.MPQ build) and produce a tracked install manifest so
`verify`, `upgrade`, `repair`, and `uninstall` work correctly afterward. This
is the tested, supported path -- see `installer/README.md` for the full
command reference. Example:

```bash
installer/bin/echoes.sh discover --azerothcore-root /path/to/your/azerothcore
installer/bin/echoes.sh install \
  --azerothcore-root /path/to/your/azerothcore \
  --mysql-user <user> --mysql-password <password> \
  --characters-database acore_characters --world-database acore_world \
  --client-root "/path/to/WoW 3.3.5a.12340"
installer/bin/echoes.sh verify --azerothcore-root /path/to/your/azerothcore
```

The installer expects your AzerothCore instance's own base
`acore_characters`/`acore_world`/`acore_auth` databases to already exist --
it layers Echoes' schema on top of an existing AzerothCore installation, it
does not set up AzerothCore itself.

**Docker-based deployment?** If your `modules/` directory lives at one path
but your actual running server's `lua_scripts/`/`etc/modules/` are
bind-mounted from elsewhere (common in Docker setups, where C++ modules are
build-time-only and never need a runtime mount), run `discover` first --
it detects this and suggests the right `--lua-root`/`--config-root` flags
for `install`/`upgrade`. See `installer/README.md`'s "Split Docker/DML-style
runtime layouts" section for the full explanation.

The rest of this document describes the equivalent **manual** process, for
anyone who prefers not to use the installer or needs to understand exactly
what it does under the hood.

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

## Step 1 — Install the C++ Modules

The mod ships as two full AzerothCore module source trees, not a patch file.
Copy them into your AzerothCore checkout's `modules/` directory:

```bash
cp -r path/to/echoes-of-the-worldsoul/cpp_patch/mod-echoes-stats \
      path/to/your/azerothcore/modules/
# Optional, only if you run mod-playerbots:
cp -r path/to/echoes-of-the-worldsoul/cpp_patch/mod-echoes-playerbots \
      path/to/your/azerothcore/modules/
```

`mod-echoes-stats` is required -- it is the engine-level application layer
for every Echoes stat/Crucible effect. `mod-echoes-playerbots` is optional
and safe to include even if you do not run Playerbots: every Playerbots
symbol it uses is guarded by `#ifdef MOD_PLAYERBOTS`, so it compiles to an
inert no-op when Playerbots is absent from your `modules/` tree.

AzerothCore's build system auto-discovers modules under `modules/*/src/` — no
`CMakeLists.txt` changes are needed.

**Rebuild AzerothCore:**

```bash
cd build
cmake ..          # re-run cmake so it picks up the new module files
make -j$(nproc)   # or your platform equivalent (MSBuild on Windows)
```

Confirm the build output mentions `mod-echoes-stats` (and `mod-echoes-playerbots`
if you copied it) being compiled.

---

## Step 2 — Apply the SQL Schema

Two sets of SQL must be run against two different databases. Order matters:
run the schema package first.

**Characters database (18 `ap_*` gameplay tables plus `ap_schema_version`,
19 tables total), in numeric order:**

```bash
for f in sql/schema/*.sql; do mysql -u [user] -p acore_characters < "$f"; done
```

(Or run each of `00_preflight.sql` through `90_validation.sql` individually,
in that order, if you prefer to inspect each step's output.)

This creates all 18 `ap_*` gameplay tables plus `ap_schema_version`. The statements are `CREATE TABLE IF NOT EXISTS`
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

Copy **every file** in `lua_scripts/` (28 files) into your server's Eluna
script folder -- do not hand-pick a subset. The default path in an
AzerothCore build is:

```
build/bin/RelWithDebInfo/lua_scripts/    (Windows, RelWithDebInfo build)
build/bin/lua_scripts/                   (Linux)
```

The numbered `ap00_*` through `ap06_*` files are foundational runtime
bootstrap scripts and must load before the rest -- Eluna's alphabetical load
order already handles this correctly as long as every file is present.
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

Using Ladik's MPQ Editor (or equivalent), or `dbc_patch/build_patch_mpq.py`
(which does steps 1-2 for you):

1. Create a new archive. Choose MPQ format version 1 (compatible with 3.3.5a).
2. Add `Item_patched.dbc` to the archive at the internal path `DBFilesClient\Item.dbc`.
3. Save the archive as `patch-E.MPQ` -- this is Echoes' reserved client-patch
   slot. Do not reuse a different letter; the installer's conflict detection
   and upgrade logic specifically identify and manage `patch-E.MPQ`.
4. Copy the finished MPQ to your WoW client's `Data\` folder.

Distribute this MPQ to any players who connect to your server, along with the
client AddOn (Step 5 below). `installer/bin/echoes.sh client-package` builds
a ready-made player package containing both, if you used the installer.

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
# Fresh install or upgrade -- the same six files, in the same order, either way
for f in sql/schema/*.sql; do mysql -u [user] -p acore_characters < "$f"; done
```

The separate numbered `sql/migrations/` files from earlier releases are gone
-- schema evolution is now handled inside `sql/schema/30_versioned_migrations.sql`
itself, via guarded (`information_schema`-checked) `ADD COLUMN`/`CREATE TABLE`
statements. Every file in `sql/schema/` is idempotent: rerunning the whole
sequence against an already-current database is a safe no-op, and rerunning
it against an older installed schema applies exactly the columns/tables that
are missing without touching existing data. `sql/schema/ap_schema_version`
(stamped by `40_seed_or_defaults.sql`) records the currently-applied version.

> **Why no separate migration-tracking table?** The guard conditions
> themselves (checking `information_schema` before every `ALTER`/`CREATE`)
> serve that purpose without a second bookkeeping mechanism. At this
> project's current scale, that is sufficient.

### Lua scripts

Copy the updated `.lua` files from `lua_scripts/` into the server's Eluna
scripts folder and run `.reload eluna` in-game, or restart the worldserver.

### AddOn (client)

Replace the `EchoesOfTheWorldsoulBridge/` folder in `Interface/AddOns/` with the
updated version. If the `## Version` field in `EchoesOfTheWorldsoulBridge.toc`
changes, the server's in-game version mismatch warning will fire for any player
still on the old version — this is the intended signal for players to update.

### C++ modules

Copy the updated `cpp_patch/mod-echoes-stats/` (and `mod-echoes-playerbots/`
if you use it) over your existing copies under `modules/`, rebuild
AzerothCore, and restart the worldserver.

### DBC / client data

Re-run `dbc_patch/patch_item_dbc.py` against a clean base `Item.dbc`,
repackage the MPQ, and distribute the updated `patch-E.MPQ` to players (or
re-run `installer/bin/echoes.sh client-package` if you used the installer).
