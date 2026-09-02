# Echoes of the Worldsoul

<p align="center">
  <img src="docs/images/echoes-of-the-worldsoul-header.png" alt="Echoes of the Worldsoul" width="100%">
</p>

[![License: GPLv3](https://img.shields.io/badge/license-GPLv3-blue.svg)](LICENSE)
[![Release](https://img.shields.io/badge/release-v2.1.4-blue.svg)](https://github.com/vibecoder99-cmd/echoes-of-the-worldsoul/releases/tag/v2.1.4)
[![AzerothCore](https://img.shields.io/badge/AzerothCore-3.3.5a-informational.svg)](https://github.com/azerothcore/azerothcore-wotlk)
[![Playerbots](https://img.shields.io/badge/Playerbots-optional-lightgrey.svg)](#playerbots-support)

A long-term progression module for AzerothCore WotLK 3.3.5a. Gear remembers
what you do with it: fight with a piece long enough and the Worldsoul begins
to answer, unlocking permanent stat power, a persistent account-wide
currency, and cosmetic effects that deepen the longer you stay attuned.

**Current release: [v2.1.4](https://github.com/vibecoder99-cmd/echoes-of-the-worldsoul/releases/tag/v2.1.4)** —
the stock-ALE compatibility corrective release. Existing progression remains
compatible and requires no reset or database wipe. Server operators using the
tested stock ALE revision must apply the included compatibility patch and
rebuild; see [INSTALL.md](INSTALL.md#stock-ale-compatibility-required-for-spending).

Open source (GPLv3), source-based install, no client modifications beyond an
additive AddOn and DBC patch.

## Start Here

New to Echoes? You don't need to know what AzerothCore, Eluna, or an MPQ
is before picking a path below — each linked page explains what it needs,
when you get there.

- **Joining a server that runs Echoes?** → [Joining an Echoes Server](#joining-an-echoes-server) / [docs/PLAYER_SETUP.md](docs/PLAYER_SETUP.md)
- **Setting Echoes up on your own server?** → [Installing Echoes on Your Server](#installing-echoes-on-your-server) / [INSTALL.md](INSTALL.md)
- **Upgrading an existing Echoes install?** → [Upgrading from v1.6.0-rc1](#upgrading-from-v160-rc1--older-echoes-installs)
- **Running Playerbots, `mod-individual-progression`, or another module alongside Echoes?** → [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)
- **Something not working?** → [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- **Want to see it before installing anything?** → [Client Companion Gallery](docs/CLIENT_COMPANION_GALLERY.md)

<p align="center">
  <img src="docs/images/client-companion/dashboard.png" alt="Client Companion Dashboard — the central hub linking every panel" width="100%">
  <br>
  <em>The Client Companion Dashboard — a full graphical AddOn, not a skin over chat commands.</em>
</p>

---

## Joining an Echoes Server

Running an Echoes server is the technical part. Playing on one shouldn't be.

If you're joining someone else's Echoes-enabled server, you do **not** need
AzerothCore, MySQL, `mod-ale`, Docker, or this project's installer. You need:

1. Your own compatible **WoW 3.3.5a (build 12340)** client — the same one
   you'd use for any AzerothCore-based server.
2. The small **Echoes client package** the server provides you: the
   `EchoesOfTheWorldsoulBridge` AddOn (a normal WoW AddOn — the same kind
   you'd install for any other UI mod) and a `patch-E.MPQ` file (a small,
   additive data patch — the client's own patch system, not a modified
   game executable; see [What does Echoes install?](#what-does-echoes-install)).
3. The server's realmlist/address, from whoever runs it.

Drop those two pieces into your client, point your realmlist at the server,
and log in. That's the entire player-side setup — see
**[docs/PLAYER_SETUP.md](docs/PLAYER_SETUP.md)** for exact folder paths and
troubleshooting.

Low on storage? You do not need to duplicate your whole WoW client. See
[What to back up first](docs/PLAYER_SETUP.md#before-you-install-what-to-back-up).

**No custom `Wow.exe`. No bundled or repacked WoW client. No Echoes server
installer. No database or server setup of any kind.** Everything past this
section is for people running the server itself, not people playing on one.

---

## What Is Echoes?

Echoes of the Worldsoul is a solo/self-paced progression layer that sits on
top of normal WotLK gameplay, built around one core idea: **your gear has a
history, and history is worth something.**

- **Attunement** — every piece of gear you fight with tracks its own
  progress. Full attunement is permanent, per-account, and survives moving
  the item between your characters.
- **Essence** — the currency attunement, kills, bosses, quests, and PvP
  earn you. It persists across sessions and is spent on permanent upgrades.
- **Mastery** — ranks up from spent Essence, permanently increasing how much
  stat power your attuned gear grants you.
- **The Crucible** — 18 categories of permanent, account-wide investment
  (Life Leech, Spell Mitigation, XP rate, and more).
- **The Attunement Rack** — up to 20 slots that let stored gear keep
  attuning passively without being equipped.
- **The Legacy Forge** — dissolve a fully-attuned item you no longer need
  into currency instead of letting it sit dead in your bags.
- **World Threat** — an optional, voluntary risk/reward challenge mode;
  higher threat means bigger rewards and real consequences for dying, not
  artificial stat inflation.
- **Visage** — cosmetic aura/flash effects that reflect how far your
  attunement has come.
- **Chaos Mode** — an optional character setting that expresses supported
  health, combat, and reference values in a larger logical unit system while
  leaving native Wrath combat and relative power relationships authoritative.

None of this requires grouping, a guild, or any other player — it's built
for a self-paced or solo-friendly server, though nothing stops it from
running on a populated one.

---

## What does Echoes install?

Echoes has both a server side and a client side. Nobody installs all of
it — players install the two client-side rows, server owners install the
rest.

| Piece | Who installs it | Where it goes | What it does |
|---|---|---|---|
| `EchoesOfTheWorldsoulBridge` (Client Companion AddOn) | Players | `Interface\AddOns\` in the WoW client | Ordinary WoW AddOn — the graphical panels, tooltips, and minimap button |
| `patch-E.MPQ` (client data patch) | Players | `Data\` in the WoW client | An additive **MPQ** (the WoW client's own archive/patch format) containing just the two custom item records Echoes needs — not a modified game executable, not a full client |
| `mod-echoes-stats` (C++ module) | Server owners | `modules/` in the AzerothCore source tree | Required. Compiled into the server; applies attunement/Crucible stat effects at the engine level |
| `mod-echoes-playerbots` (C++ module) | Server owners, optional | `modules/` in the AzerothCore source tree | Only relevant if you run **Playerbots** (a separate, optional AzerothCore bot module — see [Playerbots Support](#playerbots-support)). Compiles to an inert no-op without it |
| Lua scripts (`lua_scripts/`) | Server owners | The server's Eluna script folder | Server-side gameplay logic, run by **Eluna** (`mod-ale`) — an embedded Lua scripting engine AzerothCore uses for custom server behavior without patching the core itself |
| SQL schema (`sql/`) | Server owners | The server's MySQL/MariaDB databases | Adds Echoes' own tables plus two new item rows — never modifies existing AzerothCore tables' structure |

Players never touch the server side; server owners are not required to
distribute a full client to anyone — see
[This Is Not a Repack](#this-is-not-a-repack) for the full detail.

---

## What's New in 2.0?

If you saw Echoes at `v1.6.0-rc1`, the short version: **the interface,
the Playerbots story, and the install experience are all different now.**
This isn't a new project — it's the same design, substantially
productionized and hardened.

| | |
|---|---|
| **New** | Production **Client Companion** graphical AddOn (previously chat-command-only); optional **Playerbots integration** (`mod-echoes-playerbots`); the **installer** (`installer/`) with tracked install/verify/upgrade/repair/uninstall; the `patch-E.MPQ` client-patch namespace with automatic migration from the old `patch-4.MPQ`; a dedicated **Accessibility** settings panel; split Docker/DML-style runtime layout support (`--lua-root`/`--config-root`) |
| **Rewritten / Expanded** | Stat/Crucible-effect application moved from Lua-only approximation into `mod-echoes-stats`, a compiled, engine-level module — now a required component, not optional |
| **Productionized / Hardened** | SQL schema evolution consolidated into idempotent, guarded migrations (`sql/schema/`); a real clean-room C++ compile matrix (Playerbots present *and* absent, both actually built and linked, not inferred); a live DML-compatible deployment certification end to end |

Everything above did not appear newly invented in 2.0 in every case — some
of it (like Playerbots integration and the stat engine) existed in earlier
form during the v1.6-era development track and has now been compiled,
tested, and shipped as part of the public package for the first time. See
[Compatibility Evidence](#compatibility-evidence) for exactly what was
verified and how.

---

## What's New in 2.1?

Echoes 2.1.0 adds optional **Chaos Mode**. Chaos Power is derived from a
character's current permanent Echoes development and displayed with a
base-1000 Magnitude rank. When enabled, supported stock health numbers,
floating combat outcomes, the live Combat Log, weapon references, and bounded
fixed spell/aura/proc references use one coherent viewer-side scale.

Chaos does **not** give creatures literal billion-point native health, widen
packets, change combat resolution, add a currency, or normalize every enemy to
the player. Earlier creatures still become easier; normal mobs remain below
elites, dungeon bosses, and raid bosses. **Getting stronger must not make
Azeroth less worth playing.**

Settings contains the Chaos Numbers toggle; Progression shows Chaos Power,
Magnitude, and rank name. No Dashboard destination or new navigation was
added. See [the player guide](docs/CHAOS_MODE.md) and
[technical architecture](docs/CHAOS_ARCHITECTURE.md).

---

## Playerbots Support

**Playerbots is entirely optional.** Echoes does not require it, and every
system above works identically with zero Playerbots dependency.

`mod-echoes-playerbots` is the optional integration layer that bridges
Echoes' attunement/progression systems to Playerbots-controlled characters
(awareness, retention, Rack interaction, bounded progression spending, and
explicitly gated Dissolution). Every Playerbots-dependent symbol it uses is
guarded by `#ifdef MOD_PLAYERBOTS` in the source, so the module compiles to
an inert no-op when Playerbots isn't present in your `modules/` tree — this
isn't a design claim, it's been proven by **actually compiling the module
in both configurations** (Playerbots present and Playerbots absent), not
inferred from reading the source.

Compatibility evidence for this release:

- Real clean-room builds completed with Playerbots present (475 real
  Playerbots engine symbols linked into the resulting binary) and with
  Playerbots absent (zero engine symbols, module still fully functional).
- Historically, this integration ran live in production at approximately
  **1,700–2,000 concurrent bots** over multiple days, with no Echoes
  compatibility rollback recorded.
- Current 2.0 source, build, and installer package paths were
  independently re-verified this release.

This is **tested against the documented AzerothCore/Playerbots environment
used for this release** — it is not a claim of support for every Playerbots
fork or configuration in existence.

---

## Dad's MMO Lab / DML Compatibility

**DML-compatible / tested with Dad's MMO Lab-style environments.** This is
a compatibility statement, not an endorsement, an affiliation, or an
official Dad's MMO Lab module.

Dad's MMO Lab-style deployments commonly run AzerothCore in Docker with a
split layout: the C++ module source lives at one root, while the actual
running server's Lua scripts and config live under a separate runtime
distribution root (bind-mounted, not the checkout itself). The installer
supports this directly with explicit `--lua-root`/`--config-root` flags
(auto-suggested by `echoes discover`) — see
[installer/README.md](installer/README.md#split-dockerdml-style-runtime-layouts).

---

## Client Companion

The Client Companion (`EchoesOfTheWorldsoulBridge`) is one of the largest
visible changes since `v1.6.0-rc1`: a full graphical AddOn, not a skin over
chat commands. It's a versioned client/server protocol backed by live
server-side Echoes state, with dedicated panels for:

Dashboard · Progression · Talents · World Threat · Crucible · Attunement
Rack · Legacy Forge · Visage · Codex/Search · Settings · Accessibility

The Dashboard hero image near the top of this README is this AddOn — here's
a closer look at a few of its other panels:

<table>
<tr>
<td width="50%">
<img src="docs/images/client-companion/talents.png" alt="Worldsoul Talents panel">
<br><em>Worldsoul Talents</em>
</td>
<td width="50%">
<img src="docs/images/client-companion/crucible.png" alt="The Crucible panel">
<br><em>The Crucible</em>
</td>
</tr>
<tr>
<td width="50%">
<img src="docs/images/client-companion/attunement-rack.png" alt="Attunement Rack panel">
<br><em>Attunement Rack</em>
</td>
<td width="50%">
<img src="docs/images/client-companion/legacy-forge.png" alt="Legacy Forge panel">
<br><em>Legacy Forge</em>
</td>
</tr>
<tr>
<td width="50%">
<img src="docs/images/client-companion/visage.png" alt="Worldsoul Visage panel">
<br><em>Visage</em>
</td>
<td width="50%">
<img src="docs/images/client-companion/world-threat.png" alt="World Threat panel">
<br><em>World Threat</em>
</td>
</tr>
</table>

All 12 panels, in order, with short descriptions:
**[docs/CLIENT_COMPANION_GALLERY.md](docs/CLIENT_COMPANION_GALLERY.md)**.

---

## Installing Echoes on Your Server

**This section is for server owners/operators building and running Echoes,
not for players joining a server that already has it — see
[Joining an Echoes Server](#joining-an-echoes-server) instead if that's you.**

**Prerequisites:** an AzerothCore 3.3.5a checkout with `mod-ale` built in
(**ALE**/**Eluna** — the embedded Lua scripting engine Echoes' server-side
logic runs on; required, not optional, and checked for by the installer),
MySQL/MariaDB, and a compatible WoW 3.3.5a (build 12340) client. See
[Requirements](#requirements--compatibility) below for the full matrix.

```bash
installer/bin/echoes.sh install \
  --azerothcore-root /path/to/your/azerothcore \
  --mysql-user <user> --mysql-password <password> \
  --characters-database acore_characters --world-database acore_world \
  --client-root "/path/to/WoW 3.3.5a.12340"
```

- Add `--with-playerbots --confirm-playerbots-compatible` when deploying
  alongside `mod-playerbots`. Echoes has been validated against the
  Playerbots configuration documented for this release — check whether
  your specific fork/configuration has been tested (not "is supported")
  before relying on it in production; see [Playerbots Support](#playerbots-support).
- **Split Docker/DML-style deployment?** Run `echoes.sh discover
  --azerothcore-root ...` first — it detects the layout and suggests the
  right `--lua-root`/`--config-root` flags.
- **Fresh client, automatic `Item.dbc` extraction failed?** That's a known
  limitation (see [Fresh-Client Note](#fresh-client-itemdbc-note)), not a
  broken install — extract it once with any MPQ editor and pass
  `--vanilla-dbc-path`.
- Confirm everything landed correctly: `installer/bin/echoes.sh verify
  --azerothcore-root /path/to/your/azerothcore`

On Windows use `installer\bin\echoes.ps1` in place of `echoes.sh`. Full
walkthrough, manual (non-installer) steps, and every command's exact
semantics: **[INSTALL.md](INSTALL.md)**.

---

## Upgrading from v1.6.0-rc1 / Older Echoes Installs

The installer detects and handles a pre-installer legacy layout
automatically — run `install` (it adopts an existing deployment into
installer management) or `upgrade` (if a manifest already exists):

- **Legacy files are positively identified before anything is touched** —
  by content signature, never by filename alone. The old dev-only
  `ap_gm_aether.lua` and the legacy `mod-attunement-plus/` module (if
  present) are retired only once identified this way, and only after
  their replacements are already installed.
- **The old `patch-4.MPQ` client patch is migrated to the new `patch-E.MPQ`
  namespace** automatically, once positively identified as Echoes' own
  prior output — never touched if it can't be proven.
- **Everything is backed up before being replaced.** Nothing is deleted
  first "just in case" — see `echoes-installer-backups/` after any run.
- **Database migrations preserve existing player/progression data.**
  `sql/schema/` is idempotent and only ever adds what's missing.

Do not manually delete old files before running the installer — let it
detect and migrate them; that's exactly what the positive-identification
step is for. This does not extend to unknown, custom-forked deployments —
the guarantee above is for a genuine prior Echoes install, not an arbitrary
modification.

---

## This Is Not a Repack

Echoes is entirely source-based. This repository includes:

Lua · SQL · C++ module source · the installer · the client AddOn · DBC
patch-generation tooling · documentation

It does **not** include, and never will:

a WoW client · Blizzard client data · a custom `Wow.exe` · AzerothCore
binaries · Playerbots source · `mod-ale` source

**No custom WoW executable and no redistributed WoW client required.**
Echoes installs an additive client package into an existing, separately
obtained, compatible 3.3.5a client — it does not claim that client is
otherwise unmodified by anything else you may have installed.

**From a player's perspective:** joining an Echoes server does not require
downloading a replacement WoW executable or a full pre-modified client. You
use your own compatible 3.3.5a client plus the small Echoes client package
(`EchoesOfTheWorldsoulBridge` + `patch-E.MPQ`) provided by the server you're
joining — nothing more. See [Joining an Echoes Server](#joining-an-echoes-server).

**From a server owner's perspective:** `installer/bin/echoes.sh
client-package` generates that small package (the AddOn plus your
server's `patch-E.MPQ`) for you to distribute to your players. The public
source repository and release source package do not ship Blizzard's
`Item.dbc` or a WoW client — but the `patch-E.MPQ` you generate locally is
built from **your own** compatible `Item.dbc` and does contain that
patched client data; it is not itself Blizzard-data-free. Server owners
should not separately distribute a full WoW client, a custom `Wow.exe`,
or AzerothCore binaries — none of those are produced or required by
`client-package`. This section makes no legal claim about redistribution
rights beyond what's stated here.

---

## Requirements / Compatibility

| Component | Status | Notes |
|---|---|---|
| AzerothCore 3.3.5a | Required | Source checkout, buildable with CMake — a binary-only install is not sufficient |
| [`azerothcore/mod-ale`](https://github.com/azerothcore/mod-ale) (ALE/Eluna) | Required | External prerequisite. 2.1.4 certifies commit `9eeb1f3c...` plus the included binding patch; build with `LUA_VERSION=lua52` — see [Tested / Reference Environment](#tested--reference-environment) |
| MySQL / MariaDB | Required | `acore_characters`/`acore_world`/`acore_auth` must already exist |
| WoW 3.3.5a client (build 12340, enUS) | Required | Clean/unmodified copy — see [This Is Not a Repack](#this-is-not-a-repack) |
| Playerbots (`mod-playerbots`) | Optional | See [Playerbots Support](#playerbots-support) |
| Docker / DML-style split layout | Optional, supported | `--lua-root`/`--config-root`; auto-detected by `discover` |
| Windows | Tested | `installer\bin\echoes.ps1`; RelWithDebInfo build |
| Linux / WSL | Tested | `installer/bin/echoes.sh`; used for the live DML certification this release |
| Python 3.6+ | Required | For the installer and DBC patch tooling |

Do not read this as a guarantee across every possible AzerothCore fork or
Eluna build — see [Compatibility Evidence](#compatibility-evidence) for
exactly what was tested, and `zz_eluna_probe.lua` for a live compatibility
probe you can run against your own build.

**Known unsupported Eluna APIs** (workarounds already in place):
`RegisterCommand`, `Player:SetStat`, `Player:IsQuestRewarded`, `HasAura`,
`GetBagSize`, `GetFloat`, `Player:GetGMLevel`.

## Tested / Reference Environment

Echoes 2.1.4 is tested with official **ALE** commit
`9eeb1f3c47a81291548874fa4be2f4cde35e2ec3` plus the included
`CharDBDirectExecute` patch. ALE is the AzerothCore Lua Engine used by the
tested setup. **Do not substitute an older
`mod-eluna` fork** unless you know it matches your AzerothCore revision;
a stale fork is a common cause of confusing compile errors that look like
an Echoes problem but aren't.

| Component | Tested/reference project | Notes |
|---|---|---|
| AzerothCore | [`azerothcore/azerothcore-wotlk`](https://github.com/azerothcore/azerothcore-wotlk) | The WotLK core Echoes is built as a module for |
| Lua engine | [`azerothcore/mod-ale`](https://github.com/azerothcore/mod-ale) commit `9eeb1f3c47a81291548874fa4be2f4cde35e2ec3` + Echoes compatibility patch | Required by Echoes |
| Playerbots | [`mod-playerbots/mod-playerbots`](https://github.com/mod-playerbots/mod-playerbots) + [`mod-playerbots/azerothcore-wotlk`](https://github.com/mod-playerbots/azerothcore-wotlk) | Optional Echoes integration |
| Dad's MMO Lab | [`DadsMmoLab/dads-mmo-lab`](https://github.com/DadsMmoLab/dads-mmo-lab) | One environment Echoes has been extensively tested in — not required |
| Echoes | this repo | — |

Full stack diagram, exact known commit pins (and an honest list of what
*isn't* pinned), and DML reproduction notes:
**[docs/TESTED_ENVIRONMENT.md](docs/TESTED_ENVIRONMENT.md)**.

### Fresh-Client Item.dbc Note

The installer can automatically extract a vanilla `Item.dbc` from your
client's own stock archives (via the optional `mpyq` package). **Some real
3.3.5a MPQ variants are not fully supported by this optional extraction
path** — many retail WotLK archives use an MPQ header format `mpyq` has
incomplete support for. This is a known, documented limitation, not a
reflection of a problem with your client.

The reliable fallback: extract `DBFilesClient\Item.dbc` yourself with any
MPQ editor (e.g. Ladik's MPQ Editor), then pass
`--vanilla-dbc-path /path/to/Item.dbc`. This project does not redistribute
Blizzard's `Item.dbc` and will not link to third-party client downloads.

---

## Architecture

Six layers, each independently understandable — deliberately not blurring
"what a player installs" with "what a server owner installs":

1. **Echoes Core** (`lua_scripts/`) — the Eluna gameplay/runtime logic:
   attunement, Essence, Mastery, Crucible, Rack, Forge, World Threat,
   Visage, Chaos state/power, and the client/server protocol.
2. **Engine Integration** (`cpp_patch/mod-echoes-stats/`, required) —
   compiled, engine-level stat and Crucible-effect application.
3. **Optional Playerbots Integration** (`cpp_patch/mod-echoes-playerbots/`)
   — self-gated at compile time; see [Playerbots Support](#playerbots-support).
4. **Client Companion** (`client_addon/`) — `EchoesOfTheWorldsoulBridge`,
   the graphical player-facing UI and client/server protocol client. This
   is one of the two client-side components an ordinary player installs.
5. **Client Data Patch** (`dbc_patch/`, generated as `patch-E.MPQ`) — the
   custom `Item.dbc` records required to resolve Echoes' custom items
   (900010/900011). This is the other client-side component an ordinary
   player installs.
6. **Installer / Deployment** (`installer/`) — server-owner lifecycle
   tooling only: SQL migrations, manifest, backups,
   install/verify/upgrade/repair/uninstall, and generating the Client
   Companion + `patch-E.MPQ` package server owners hand to players.

---

## Repository Structure

```
echoes-of-the-worldsoul/
├── installer/             Python installer core + Bash/PowerShell wrappers
│                           (install, verify, upgrade, repair, uninstall,
│                           client-package, discover) + regression tests
├── lua_scripts/            Server-side Eluna Lua scripts (28 files)
├── cpp_patch/
│   ├── mod-echoes-stats/       Required -- engine-level stat/Crucible-effect application
│   └── mod-echoes-playerbots/  Optional -- Playerbots integration, self-gated at compile time
├── sql/
│   ├── schema/             00_preflight.sql .. 90_validation.sql -- idempotent install package
│   └── data/               world_items.sql -- custom item rows (acore_world)
├── dbc_patch/              patch_item_dbc.py, mpq_writer.py, build_patch_mpq.py, tooling docs
├── client_addon/           EchoesOfTheWorldsoulBridge WoW AddOn (Client Companion)
├── docs/                   API.md, EXTENSIONS.md, PLAYER_SETUP.md, compatibility evidence ledger
├── .github/                Issue templates
├── INSTALL.md
├── CHANGELOG.md
├── RELEASE_NOTES_v2.0.0-rc1.md
├── RELEASE_NOTES_v2.1.0.md
├── RELEASE_NOTES_v2.1.1.md
├── ECHOES-2.1.4-RELEASE-NOTES.md
├── LICENSE
└── README.md
```

Not included in this repository: `mod-ale` and `mod-playerbots` (both
external prerequisites — see Requirements above).

---

## Configuration

Server-runtime gameplay tuning (attunement rates, Essence rewards, Mastery
thresholds, Crucible sink caps, Rack slot costs, Forge rewards, Visage
themes) lives in `ap_core.lua`'s `AP.Config` table and the respective
`ap_*.lua` files — edit and use the supported `reload.ale` operator command,
no database change or
restart needed. C++ module settings (`EchoesStats.*`,
`EchoesPlayerbots.*`) live in `etc/modules/*.conf` and take effect on
restart. Client-side preferences (Accessibility, UI options) are stored by
the AddOn itself and never touch the server.

---

## Testing

**Developer testing only (GM-enforced):** `#aptest` runs the full regression suite — 20 suites,
214 individual tests, covering math, database, tooltip, anti-spam, quest,
aether, UI, Forge, Residue, Crucible, Visage, PvP, voice, versioning,
exploit guards, and every numbered tier's fixes. Run an individual suite
with e.g. `#aptest tier6` or `#aptest threat`. It mutates reserved database
fixtures, refuses to run without `CharDBDirectExecute`, and should not be used
as an ordinary player or production troubleshooting command.

**Installer regression (Python, disposable fixtures only):** 200+
assertions across single-root, split-root, legacy-migration, and
attack-style test files, re-run from an extracted release artifact as
part of this RC's own preparation.

**C++ module tests:** 247/247 assertions passing across the module's
standalone unit test files.

**Clean-room compile evidence:** real compiled builds with Playerbots
present and absent, not inferred.

These are separate, non-comparable test populations — see
[Compatibility Evidence](#compatibility-evidence) below rather than
adding them together.

---

## Compatibility Evidence

Most users won't need to read the full technical ledger. Summary of what
was independently verified for this release:

- Clean-room C++ builds with Playerbots present and absent (both actually
  compiled and linked)
- DML-style and generic-AzerothCore installer walkthroughs
- The split Docker/DML-style runtime layout fix, verified live against a
  real deployment
- A package-equivalent server built and booted from the installer's own
  output
- Client Companion package reproduction: 273/273 files byte-identical to
  a real deployed install
- Live `patch-4.MPQ` → `patch-E.MPQ` migration, verified against a real
  client
- Full live client route/action validation (login, item resolution, every
  Client Companion panel, one reversible server-backed action)
- Historical Playerbots load validation at ~1,700–2,000 concurrent bots

Full evidence, methodology, and every individual finding:
**[docs/COMPATIBILITY-ATTACK-DEFECT-LEDGER.md](docs/COMPATIBILITY-ATTACK-DEFECT-LEDGER.md)**.

---

## Compatibility & Common Module Stacks

Echoes is being tested against common AzerothCore and Playerbots module
combinations rather than claiming universal module compatibility. The
matrix below distinguishes combinations that have been empirically
tested from modules that are only planned compatibility targets.

| Module | Status |
|---|---|
| Playerbots (`mod-playerbots`) | **TESTED** — see [Playerbots Support](#playerbots-support) |
| `mod-individual-progression` (`ZhengPeiRu21`, tested at commit `df10164`) | **SERVER TESTED / CLIENT MERGE REQUIRED** |
| `mod-transmog`, `mod-autobalance`, `mod-solo-lfg`, `mod-ah-bot-plus`, `mod-aoe-loot`, `mod-challenge-modes`, `mod-progression-system`, `mod-solocraft` | TARGET — not yet tested |
| Random-enchant / reforge-style item-mutation modules | **HIGH-RISK TARGET** |

None of the TARGET entries above are compatibility claims — they're the
priority list for what gets tested next. Full detail, exact repositories
and commits, the mod-individual-progression client-patch requirement,
testing methodology, and how to report your own module combination:
**[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)**.

---

## Extension API

Echoes exposes `AP.API` for future dependent modules (Empire, Prestige,
Companions, Fusion Forge, etc.) — see [docs/API.md](docs/API.md) and
[docs/EXTENSIONS.md](docs/EXTENSIONS.md). Extensions register via
`AP.API.RegisterExtension()` and subscribe to game events via
`AP.API.RegisterHook()`; hook dispatch is pcall-safe, so one extension's
error can't crash the base module.

---

## Getting Help

- **Just joining a server?** See [Joining an Echoes Server](#joining-an-echoes-server)
  and [docs/PLAYER_SETUP.md](docs/PLAYER_SETUP.md) first.
- **Bugs and compatibility reports:** [GitHub Issues](https://github.com/vibecoder99-cmd/echoes-of-the-worldsoul/issues/new/choose)
  — please include your AzerothCore revision, Eluna version, OS,
  single-root/split-layout, installer-or-manual install, Playerbots
  presence, client build, and any relevant logs.
- **Installation questions, "will this work for me," general discussion:**
  [GitHub Discussions](https://github.com/vibecoder99-cmd/echoes-of-the-worldsoul/discussions)
- **Troubleshooting common issues:** [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

Please do not include database passwords, credentials, or other secrets in
issue reports.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

See [SECURITY.md](SECURITY.md) for how to report a security-relevant issue
(e.g. installer path handling, unsafe database behavior).

---

## Acknowledgments

Echoes was originally inspired by the item-attunement system of the
**Synastria** WoW private server, and later by **Peloria**'s more recent
approach to permanent item-based progression. Echoes is independently
implemented from scratch for AzerothCore — its own design, database
schema, Lua architecture, and feature set. No affiliation with or
endorsement by either project is claimed. The motivation is simple: make
this style of permanent, gear-driven progression available to anyone
running their own AzerothCore environment, not just players of those
specific servers.

Developed with the assistance of **Claude** (Anthropic) as an AI pair
programmer.

Special thanks to **PRAN**, Level 80 Orc Warrior, who endured every crash,
exploit, and item-loss incident this project produced during the original
Eluna-era test campaign and is still standing — and to the many
short-lived Orc Warrior clones created, tested, and deleted in his shadow,
whose sacrifices were no less essential and whose names history does not
record.

And to **BRUS**, Level 4 Human Warrior, principal live test character of
the compatibility-hardening, Dad's MMO Lab, Playerbots, and Client
Companion era — proof that you don't need to be high level to do
important, dangerous work.

---

## License

Copyright (C) 2025-2026 vibecoder99.
Licensed under the GNU General Public License v3.0 or later. See `LICENSE`.
