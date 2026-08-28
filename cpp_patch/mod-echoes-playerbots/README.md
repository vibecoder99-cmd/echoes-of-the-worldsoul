# mod-echoes-playerbots

Optional, fail-dormant **Layer 1 (Awareness)** integration between the
Echoes of the Worldsoul Lua package and mod-playerbots, for the DML
AzerothCore Playerbots server.

Prototype status: this module implements the smallest useful behavior only —
*a Playerbot will not discard or replace meaningfully attuned equipped gear
for a merely marginal base-stat upgrade.* It does not implement Rack,
Forge, dissolve, economy planning, dialogue, or any progression strategy.
See `env/backups/e2i1/.../reports/e2i1-closure-report.md` for the full
architecture this module implements, and
`env/backups/e2i2/.../reports/e2i2-closure-report.md` for this prototype's
validation evidence.

## Design contract

- **Optional and disabled by default.** `EchoesPlayerbots.Enable = 0` out of
  the box. Nothing about this module's presence changes any behavior until
  explicitly enabled *and* a compatible Echoes runtime is confirmed present.
- **Fail dormant.** If Echoes is absent, its schema is missing/incompatible,
  or this module is disabled, zero recurring database queries are issued
  and Playerbots behaves exactly as if this module did not exist.
- **Zero modification to upstream mod-playerbots or AzerothCore core.**
  This module consumes only mod-playerbots' own public interface
  (`GET_PLAYERBOT_AI()`, `StatsWeightCalculator`) and standard, unmodified
  AzerothCore `PlayerScript`/`WorldScript` hooks
  (`OnPlayerCanEquipItem`, `OnPlayerLogin`/`OnPlayerLogout`,
  `OnStartup`/`OnUpdate`/`OnShutdown`).
- **Human-player isolation is absolute.** Every hook checks
  `GET_PLAYERBOT_AI(player)` first; a human player never enters any Echoes
  decision path, never gets a cache entry allocated, and never has an
  Echoes-integration query executed on their behalf.
- **Read-only with respect to Echoes state.** This module never writes to
  any `ap_*` table. It only reads `ap_schema_version` (presence handshake)
  and `ap_item_attune` (per-decision attunement lookup).

## Build

Auto-discovered by the existing AzerothCore module system — no changes to
any existing CMake file were made or are required. Any directory under
`modules/` containing a `src/` subdirectory is picked up automatically
(`GetModuleSourceList` in `src/cmake/macros/ConfigureModules.cmake`) and
statically linked into the worldserver when built with `-DMODULES=static`
(the configuration already used throughout this project).

## Configuration

See `conf/mod_echoes_playerbots.conf.dist`.

## Tests

`tests/EchoesAwarenessTests.cpp` is a standalone, dependency-free unit test
for the entire Layer 1 decision policy (`EvaluateAwareness`, in
`src/EchoesAwareness.h/.cpp`). It is intentionally placed outside `src/`
so it is never linked into the worldserver binary. Compile and run it
directly:

```
cd tests
g++ -std=c++17 -I../src ../src/EchoesAwareness.cpp EchoesAwarenessTests.cpp -o echoes_awareness_tests
./echoes_awareness_tests
```

## License

GNU General Public License v2 (see `LICENSE.md`), for compatibility with
mod-playerbots, which this module optionally interoperates with. Echoes of
the Worldsoul's own Lua package is unaffected and unmodified by this module
under any circumstance.
