# Echoes of the Worldsoul — Public API

## Overview

`AP.API` provides a stable read-only interface for extension modules to query player progression state without accessing internal tables or DB queries directly.

All functions accept a `player` object and return safe defaults if data is missing.

## Version & Readiness

```lua
AP.API.GetVersion()       -- returns "1.0.0"
AP.API.IsReady()          -- true after AP.Config and AP.InitDB are loaded
```

## Player Data

```lua
AP.API.GetEssence(player)              -- current Essence (Aether) balance
AP.API.GetWorldsoulResidue(player)     -- current Worldsoul Residue balance
AP.API.GetMasteryRank(player)          -- mastery rank (0+)
AP.API.GetBaseAbsorption(player)       -- base absorption % (0.0-1.0)
AP.API.GetLevelScalar(player)          -- level-based scalar (0.0-1.0)
AP.API.GetEffectiveAbsorption(player)  -- base * level scalar
AP.API.GetTotalAttunedCount(player)    -- total fully-attuned items
AP.API.GetRackCount(player)            -- returns used, capacity
```

## Threat System

```lua
AP.API.GetThreatLevel(player)          -- 0-10
AP.API.GetThreatMomentum(player)       -- 0.0-1.0
AP.API.GetThreatMultiplier(player)     -- effective multiplier (1.0-2.0)
AP.API.GetThreatDebt(player)           -- { kills=N, mult=X }
AP.API.GetPlayerSession(player)        -- raw session table (advanced)
```

## Visage

```lua
AP.API.GetVisageState(player)
-- Returns: {
--   primary_theme, primary_enabled, primary_tier,
--   secondary_theme, secondary_enabled, secondary_tier
-- }
```

## Progression Summary

```lua
AP.API.GetProgressionSummary(player)
-- Returns complete table with all fields above
```

## Safety

- All functions return safe defaults (0, "", {}) for nil/missing data
- No function modifies game state — read-only
- pcall-wrapped internally where player methods are called
