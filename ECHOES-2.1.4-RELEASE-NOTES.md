# Echoes of the Worldsoul 2.1.4

## Stock ALE compatibility corrective release

Echoes 2.1.4 closes the compatibility gap between guarded Echoes spending and
official stock AzerothCore Lua Engine (ALE). The release includes a minimal,
reviewable C++ binding patch that exposes `CharDBDirectExecute` to Lua without
adding Echoes gameplay logic to ALE.

The compatibility artifact is locked to official `azerothcore/mod-ale` branch
`master`, commit `9eeb1f3c47a81291548874fa4be2f4cde35e2ec3`:

- patch: `compat/mod-ale/0001-expose-chardb-directexecute.patch`
- canonical-LF SHA-256:
  `87cbd3d08d8ae5a73d4ef7c7e176bdc342d4676c15eb2e4aef9f2ab8a1547b82`
- ALE files changed: `src/LuaEngine/LuaFunctions.cpp` and
  `src/LuaEngine/methods/GlobalMethods.h`
- binding added: `CharDBDirectExecute`

Run `echoes ale-compat --azerothcore-root ...` first. This is a dry-run and
does not modify ALE. Add `--apply` only after reviewing the detected revision.
Unknown revisions are refused. After applying, reconfigure/rebuild
`worldserver`, restart it safely, run `echoes verify`, and confirm runtime
startup reports `CharDBDirectExecute: YES`.

This release does not change gameplay, balance, progression, schema, client
protocol, or stored player data. Protocol version remains 1. No reset or wipe
is required.

## Release certification

The unmodified and patched official ALE trees both compiled and linked a full
`worldserver` in an isolated Ubuntu 24.04 / Clang 18 build with Lua 5.2 and
static modules. The patched binary contains the `CharDBDirectExecute` symbol.

The targeted 2.1.4 validation matrix passes. One unrelated historical
wording-contract check remains at 35/36: its `active=false` guard assertion
cannot locate the current deduction expression (`deduct_idx=-1`). The exact
failure and both implicated file hashes are identical at starting commit
`7f4efbcf91cc3903299357ed825a989bcc9e890d` and in 2.1.4, so it is classified
pre-existing/non-regression rather than reported as a green repository-wide
pytest result.

Historical clarification: 2.1.2 and 2.1.3 correctly failed guarded spending
closed when this binding was absent, but their guidance did not supply the
stock-ALE compatibility path now included in 2.1.4.

Special thanks to community tester snakeshot
(Reddit: Economy_Progress6405 / Weird_Expert_1999)
for tracing the stock ALE compatibility gap down to the missing Lua database
binding.
