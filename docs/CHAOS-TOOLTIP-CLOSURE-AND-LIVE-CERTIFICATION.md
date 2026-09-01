# Chaos Tooltip Closure and Live Certification — 2026-08-31

## Outcome

Implemented a bounded, deterministic personal-reference layer for fixed spell/aura/proc quantities without rewriting Blizzard prose. Native combat mechanics were not changed.

## Supported

- fixed direct damage/ranges;
- fixed periodic damage/totals;
- fixed direct/periodic healing;
- reliable fixed absorbs;
- single-line fixed Chance on hit / Equip / Use effects.

All static references use `Chaos:GetPersonalScale()`. Actual combat events remain destination/recipient-scaled.

## Native/deferred

Percentages, attributes, AP/SP/armor, costs/resources, durations/ranges, dynamic/coefficient/scripted effects, unreliable absorbs, multiline proc prose, and unsupported localization remain native.

## Lifecycle

`GameTooltip` and `ItemRefTooltip` use one synchronous post-native `OnTooltipSetSpell` hook. Item procs use the existing bridge augmentation seam after Attunement and weapon references. There is no ClearLines replay, SetHyperlink reconstruction, OnUpdate rebuild, or broad prose replacement.

## Evidence

Automated suites passed. Live Wrath 3.3.5a observation on Brus (level 4):

- Chaos ON PlayerFrame: `104K / 104K`;
- Rend retained native text and appended one periodic reference (`~22.20K` for the reliable fixed 25-damage base);
- Chaos OFF restored stock PlayerFrame presentation without reload;
- `/reload` succeeded;
- no stale version warning appeared.

Subsequent user validation covered persisted-ON relog, character switching,
Mage/Warlock spell behavior, floating output, live Combat Log values, broad NPC
samples, Magnitude I believability, and stable tooltip behavior. Verdict:
**GREEN** for the defined 2.1.0 scope.

## Persisted-state lifecycle repair

A later release-blocking audit found two edge-trigger gaps: persisted `chaos_enabled=1` could be ingested before `Chaos.lua` subscribed, and a normal logout could restore native CVars before a byte-identical same-character STATE was discarded as unchanged. In both cases Settings could read ON while presentation was not reapplied.

`Chaos:ApplyAuthoritativeState` now receives the current StateStore snapshot immediately after subscription and every authoritative server STATE, including unchanged snapshots. Toggle responses, initial login hydration, relog/reload hydration, and character changes therefore use one projection seam. Focused regressions cover persisted ON/OFF, unchanged same-character relog replay after `PLAYER_LOGOUT`, repeated ON/OFF, reload-style reapplication, A ON → B OFF → A ON, exact CVar and alpha baseline restoration, and singular tooltip behavior. Controlled post-fix same-character relog and character switching were manually verified by the user, so the release verdict is **GREEN**.
