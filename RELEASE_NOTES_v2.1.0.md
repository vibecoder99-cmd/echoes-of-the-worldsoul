# Echoes of the Worldsoul v2.1.0 — Chaos Mode

## Highlights

- Optional, character-scoped Chaos Mode with current-state-derived Chaos Power,
  base-1000 Magnitude, and named ranks.
- Coherent viewer-side Effective Health across supported stock frames,
  destination-scaled floating combat outcomes, and Blizzard's live Combat Log.
- Personal Chaos references for weapons and supported fixed spell/aura/proc
  quantities.
- Authoritative persisted-state restoration across login, reload, relog, and
  character switching without changing native combat or widening stats.
- Mixed normal/Chaos play remains supported because the setting affects only
  each viewer's presentation.

## Fixes

- Removed contradictory native/Chaos health and combat-number presentation on
  supported ordinary HUD surfaces.
- Stabilized deterministic tooltip ordering and eliminated the observed
  tooltip-flicker rebuild path.
- Replayed already-hydrated and unchanged authoritative state so persisted ON
  presentation returns without manual OFF/ON cycling.
- Updated server/AddOn expected-version agreement to 2.1.0.
- Corrected the touched 64-bit Aether state read through `AP.DB.GetUInt64`.

## Known boundaries

- Third-party AddOns may continue to display native values.
- Unsupported dynamic or localization-ambiguous tooltip prose remains native.
- GM/debug/admin output intentionally remains native.
- Raid/focus-target numeric surfaces are not certified in this release.
- A historical manual Combat Log refilter/reopen path remains a P2 boundary.

Upgrade instructions are in [INSTALL.md](INSTALL.md); player-facing behavior is
documented in [docs/CHAOS_MODE.md](docs/CHAOS_MODE.md).
