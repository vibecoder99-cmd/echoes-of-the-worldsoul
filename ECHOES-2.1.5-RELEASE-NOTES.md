# Echoes of the Worldsoul 2.1.5

Echoes 2.1.5 fixes an installer crash introduced by the regression-test
directory included in 2.1.4.

The installer previously treated every entry under `lua_scripts/` as a regular
file. Because 2.1.4 added `lua_scripts/tests/`, installation could stop with
`IsADirectoryError` before runtime Lua deployment completed.

2.1.5 explicitly deploys only regular root-level runtime `.lua` files, in
deterministic name order. Developer/test directories are excluded from the live
ALE directory and from installer manifest ownership and hashing. An isolated
end-to-end fixture now proves installation and verification succeed with the
exact failing source-tree shape while `tests/` remains absent at the
destination.

The stock-ALE compatibility fix introduced in 2.1.4 is unchanged. Users who
already applied that patch, rebuilt worldserver, and verified
`CharDBDirectExecute: YES` do not need to apply it again.

No progression reset, database wipe, AzerothCore reinstall, gameplay change,
or ALE compatibility semantic change is included. The Client Companion
protocol remains version 1.

Special thanks to community tester snakeshot
(Reddit: Economy_Progress6405 / Weird_Expert_1999) for identifying the
installer packaging issue and confirming the repaired 2.1.4 backend
functionality in a real Debian 13 environment.
