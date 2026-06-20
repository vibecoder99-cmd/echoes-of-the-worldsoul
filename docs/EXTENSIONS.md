# Echoes of the Worldsoul — Extension System

## Overview

Future modules (Empire, Prestige, Companions, Fusion Forge, etc.) depend on Echoes of the Worldsoul as their base. The extension system provides registration, hooks, and a clean API boundary.

## Registering an Extension

```lua
AP.API.RegisterExtension("my_module", {
    name        = "My Module",
    version     = "0.1.0",
    requires    = { "echoes_base" },
    description = "Does something cool",
})
```

- `id` must be a non-empty string (unique per extension)
- Registration is runtime-only (no DB needed)
- Query registered extensions: `AP.API.GetExtensions()`

## Hook System

Extensions subscribe to game events without modifying core files.

### Registering a Hook

```lua
AP.API.RegisterHook("OnItemAttuned", "my_module", function(payload)
    -- payload.guid, payload.itemEntry, payload.progress
end)
```

### Available Hooks

| Hook Name | Payload Fields | When |
|---|---|---|
| OnItemAttuned | guid, itemEntry, progress | Item reaches full attunement |
| OnThreatChanged | guid, oldLevel, newLevel, momentum | Player changes threat level |
| OnThreatDeathPenalty | guid, threat, essenceLost, attuneLost, debtKills | Player dies at threat 1+ |
| OnForgeDissolve | guid, itemEntry, essenceReward, residueReward | Item dissolved in Forge |
| OnVisageChanged | guid, field, oldValue, newValue | Player changes visage theme |

### Safety

- All hooks are dispatched via `pcall` — one extension error cannot crash the base module
- Extension errors are logged via `AP.Debug` (visible only when `AP.Config.Debug = true`)
- Hook dispatch order is not guaranteed
- Do not return values from hooks — they are fire-and-forget

## Reading Player State

Use `AP.API` functions (see docs/API.md) rather than accessing `AP._session`, `AP.Visage.Cache`, or DB tables directly.

## Rules for Extension Authors

1. Register your extension on load with `AP.API.RegisterExtension`
2. Use hooks instead of patching core files
3. Read state through `AP.API`, not internal tables
4. Do not write to `ap_session_state`, `ap_mastery`, or other core tables directly
5. Create your own tables for extension-specific data
6. Gate your UI behind your own module-enabled check
7. Use `AP.Try` for error-safe operations
