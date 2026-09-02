# Echoes of the Worldsoul 2.1.2

> Historical compatibility clarification (added in 2.1.4): 2.1.2 correctly
> fails guarded spending closed when `CharDBDirectExecute` is absent, but the
> tested stock ALE revision does not provide that binding without the
> version-locked compatibility patch shipped in Echoes 2.1.4.

## Reliability & Runtime Compatibility Hotfix

Echoes 2.1.2 is a focused reliability hotfix following real-world installation
and runtime testing. It does not add a new gameplay system or change the Client
Companion wire protocol.

## Highlights

- Talent purchases now debit Essence and advance the selected rank in one
  guarded atomic transition, followed by an authoritative read-back.
- Mastery purchases now reject stale or concurrent state instead of
  overwriting it or reporting an unverified success.
- Crucible investment now moves Essence and invested value in one atomic
  multi-table operation, closing the previous crash interval between debit and
  credit.
- Echoes now initializes from ALE's post-script-load Lua-state event on fresh
  startup and after `reload.ale`. The old DML-specific first-update workaround
  and hardcoded environment identity were removed.
- Startup diagnostics now report a missing `CharDBDirectExecute` capability as
  unsupported instead of saying the system is OK.
- The `#aptest` developer harness now requires a positively identified GM and
  synchronous fixture-write support.

## Upgrade

Existing progression is compatible. No character reset, AzerothCore reinstall,
or database wipe is required. Upgrades from both 2.1.0 and 2.1.1 preserve
attunement, Essence, Mastery, Talents, Rack state, Crucible investment, Forge
history, Visage state, and Client Companion settings.

Upgrade the server package and Client Companion AddOn together using the normal
installer workflow with `--target-version 2.1.2`.

## Important ALE requirement

The running ALE build must expose `CharDBDirectExecute` for guarded purchase
operations. Directory presence alone does not prove this API exists. Run
`echoes verify` and inspect the runtime capability output.

If the API is unavailable, Echoes fails guarded writes closed rather than
risking a partial update or false-success response. Install or upgrade to a
compatible `mod-ale` build; do not wipe progression or edit purchase Lua.

## Startup lifecycle

The historical DML-specific startup workaround has been removed. Echoes now
uses ALE event 33, the factual post-script-load Lua-state signal, and initializes
at most once for each fresh or reloaded Lua state.

## Known limitation

World Threat persistence remains asynchronous. The latest Threat setting may
revert if worldserver crashes immediately after it changes. This does not lose
currency or items and does not corrupt progression.

## Community testing

Special thanks to community tester snakeshot, who reached me through the Reddit
accounts Economy_Progress6405 and Weird_Expert_1999. His detailed real-world
testing, troubleshooting video, logs, and reports directly helped identify the
reliability and interaction-feedback issues addressed across the recent Echoes
updates.
