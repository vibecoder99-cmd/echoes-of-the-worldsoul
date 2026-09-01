# Troubleshooting / FAQ

## `#ap` does nothing / no response in-game

Check the worldserver console/log for Lua load errors first (`.reload
eluna` in-game will surface a fresh error if one exists). Confirm all 28
files from `lua_scripts/` were copied — not a hand-picked subset — since
several are foundational runtime bootstrap scripts other files depend on.

## Compile errors after installing "Eluna"

If you see compile failures involving old AzerothCore API names such as
`QueryNamedResult`, first confirm you cloned the tested
[`azerothcore/mod-ale`](https://github.com/azerothcore/mod-ale) repository
rather than an older `mod-eluna` fork — this is a strong diagnostic clue,
not proof of the only possible cause, but it's the first thing to rule
out. Check, in order:

1. Which exact repo you cloned (`git remote -v` in that module's folder)
2. That it's under your AzerothCore checkout's `modules/` directory, not
   somewhere else
3. Your current AzerothCore revision — an old fork paired with a new
   AzerothCore (or vice versa) can produce API-mismatch errors that look
   identical to a missing-dependency error
4. Only once the module's identity and AzerothCore revision are confirmed
   correct, treat remaining errors as a genuine build/Lua-headers issue

Don't jump straight to chasing missing packages or Lua header versions
before confirming you actually have the right module in the first place
— see [docs/TESTED_ENVIRONMENT.md](TESTED_ENVIRONMENT.md) for the exact
tested repository.

## Lua doesn't load / Eluna errors on startup

Confirm `mod-ale` is actually compiled into your build (`installer
discover --azerothcore-root ...` reports `has_mod_ale`), and that it was
built with `LUA_VERSION=lua52` — this project's Lua targets 5.2, not the
more common 5.1. Run `zz_eluna_probe.lua`'s output at startup as a direct
compatibility check.

## Installer says `mod-ale` is missing

This is the same prerequisite as "Eluna" elsewhere in the docs — the
installer checks for `modules/mod-ale/` under your `--azerothcore-root`.
If you have Eluna built in under a different module name or location, the
installer can't detect it; this is a real external prerequisite, not
optional.

## C++ module not compiled / stat effects don't apply

`mod-echoes-stats` is required and statically links into `worldserver` --
there's no binary-only install path. After copying the module (or running
the installer), re-run `cmake` and rebuild; confirm the build output
actually mentions `mod-echoes-stats` compiling.

## Database tables missing / SQL errors

Run `sql/schema/*.sql` (or `installer ... install`) against
`acore_characters` *before* enabling the Lua scripts -- some AzerothCore
builds hard-abort on missing columns/tables during DB queries. The schema
package is idempotent; re-running it is always safe.

## Custom items (900010/900011) show as question marks

The client's `Item.dbc` wasn't patched, or the patched `patch-E.MPQ` isn't
in `Data/`. See the [Fresh-Client Item.dbc Note](../README.md#fresh-client-itemdbc-note)
in the README if automatic extraction failed.

## Installer error: "already exists and is not recorded as an Echoes-generated file" (patch-E conflict)

This is an intentional safety check, not a bug: an unknown `patch-E.MPQ`
already exists at that path and the installer can't prove it's Echoes'
own output, so it refuses to overwrite it rather than risk destroying
someone else's client data -- there is no `--force` override in the
ordinary install path. Resolve the collision by renaming/removing the
conflicting file (if you're sure it's not something else's data) or
install without `--client-root` to skip client patching for now.

## Old `patch-4.MPQ` / legacy Echoes install

If your `Data/patch-4.MPQ` is positively identified as Echoes' own prior
output (by content signature, not filename), the installer migrates it to
`patch-E.MPQ` directly and retires the old file automatically -- no
vanilla `Item.dbc` extraction needed for this path. See
[Upgrading from v1.6.0-rc1](../README.md#upgrading-from-v160-rc1--older-echoes-installs).

## Fresh-client `Item.dbc` extraction fails

See the [Fresh-Client Item.dbc Note](../README.md#fresh-client-itemdbc-note)
-- this is a known, documented limitation of the optional `mpyq`
extraction path against some real client archive formats, with a reliable
`--vanilla-dbc-path` fallback.

## Playerbots integration isn't active even though the module is installed

The installer never auto-enables `EchoesPlayerbots.Enable` -- it requires
an explicit `--confirm-playerbots-compatible` flag at install time (a
deliberate safeguard: never inferred from `mod-playerbots` merely being
present). Run `verify` to see the recorded reason.

## Split Docker/DML-style root confusion

If your `modules/` directory is separate from your actual running
server's `lua_scripts/`/`etc/modules/` (common in Docker setups), run
`echoes discover --azerothcore-root ...` -- it detects this and prints the
exact `--lua-root`/`--config-root` flags to use. See
[installer/README.md](../installer/README.md#split-dockerdml-style-runtime-layouts).

## AddOn shows as "out of date" at character select

Enable **Load out of date AddOns** at the character-select AddOns screen.
This is a normal WoW client setting, not an Echoes-specific issue.

## Lua errors from the Client Companion AddOn

Enable `Interface Options -> Display Lua Errors` (or use an error-catching
addon) and report the exact error text via GitHub Issues, including your
AddOn version (`## Version` in `EchoesOfTheWorldsoulBridge.toc`).

## Client shows `Error #132` after installing patch-E.MPQ

This is the classic "corrupted/mismatched DBC" client error. It usually
means the `Item.dbc` used to build `patch-E.MPQ` wasn't genuinely vanilla
(already modified by another patch). Rebuild from a confirmed-clean
`Item.dbc` extraction.

## `verify` reports modified files

`verify` compares installed files against the manifest's recorded hashes.
A reported mismatch means something changed the file outside the
installer's own management -- if that was intentional (e.g. hand-tuned a
`.conf`), no action needed. If it wasn't, `repair --restore-mismatched`
restores it from the current package source (missing files are always
restored automatically; mismatched ones only with that explicit flag).

## Chaos toggle is ON but native numbers still appear

Confirm both the server package and `EchoesOfTheWorldsoulBridge.toc` report
`2.1.0`; a mixed 2.0/2.1 pair lacks the complete Chaos contract. `/reload` is
safe. Supported stock Player, Target, Focus, Pet, Party 1–4, and vehicle-bound
PlayerFrame numeric health should use Chaos units when stock numbers would be
visible. Third-party frames/meters may still show native values by design.

## Chaos state does not survive relog or character switching

Chaos is persisted per character in `ap_mastery.chaos_enabled`. Verify the
2.1.0 guarded schema ran and server STATE includes `chaos_enabled` and
`chaos_power`. Manual OFF/ON cycling is not the initialization mechanism in
2.1.0; capture exact Lua/server errors and both version strings before changing
SavedVariables.
# Spending fails while Essence still accrues

Do not wipe progression or reinstall AzerothCore. First run `echoes discover`
and `echoes verify`, then check the worldserver's Eluna probe output for
`CharDBDirectExecute: YES`. Accrual and state reads can work on an older ALE
build even though Echoes correctly refuses critical purchases without this
synchronous write API. Also confirm that the live Lua directory—not a
disconnected source-root copy—contains one coherent Echoes version.
