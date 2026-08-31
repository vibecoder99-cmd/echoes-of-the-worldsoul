# Tested / Reference Environment

This page answers one question precisely: **what exact upstream projects and
repositories does Echoes' testing actually use?** It exists because "Eluna"
alone isn't a specific enough answer — there are multiple forks in the wild
with that name, and using the wrong one is a common source of confusing
compile errors that have nothing to do with Echoes itself.

## 1. Core Stack

Echoes sits on top of a small, ordered dependency chain:

```
WoW 3.3.5a (build 12340) client
        │
AzerothCore (3.3.5a core)
        │
mod-ale  (Lua engine — required)
        │
Echoes server modules (lua_scripts/, mod-echoes-stats)
        │
mod-playerbots  (optional integration)
        │
Echoes client AddOn + patch-E.MPQ
```

Everything below `mod-ale` in this chain is Echoes itself; everything above
it is external and not distributed in this repository.

## 2. Canonical Upstream Links

| Component | Upstream project | Notes |
|---|---|---|
| AzerothCore | [`azerothcore/azerothcore-wotlk`](https://github.com/azerothcore/azerothcore-wotlk) | The WotLK server core Echoes is built as a module for |
| Lua engine | [`azerothcore/mod-ale`](https://github.com/azerothcore/mod-ale) | **Required.** See the ALE clarification below |
| Playerbots core (AzerothCore fork) | [`mod-playerbots/azerothcore-wotlk`](https://github.com/mod-playerbots/azerothcore-wotlk) (Playerbot branch) | Only needed if you also want Playerbots |
| Playerbots module | [`mod-playerbots/mod-playerbots`](https://github.com/mod-playerbots/mod-playerbots) | Optional Echoes integration — see [Playerbots Support](../README.md#playerbots-support) |
| Dad's MMO Lab | [`DadsMmoLab/dads-mmo-lab`](https://github.com/DadsMmoLab/dads-mmo-lab) | One environment Echoes has been extensively tested in — not required |
| Dad's MMO Lab WotLK guide | [`guides/wow-wotlk`](https://github.com/DadsMmoLab/dads-mmo-lab/blob/main/guides/wow-wotlk/README.md) | Covers a from-scratch AzerothCore + Playerbots WotLK setup |
| Echoes | this repository | — |

**Important ALE clarification:** Echoes is tested with AzerothCore's current
ALE module (`azerothcore/mod-ale`) — **ALE** stands for "AzerothCore Lua
Engine," the actively-maintained successor to the original Eluna project,
now published under the AzerothCore organization itself. Do not substitute
an older `mod-eluna` fork (for example `araxiaonline/mod-eluna` or
`gultask/mod-eluna`) unless you specifically know it matches your
AzerothCore revision — stale forks are a common source of compile errors
that look like an Echoes problem but aren't.

## 3. Exact Known Commit Pins

Being precise about what actually has a recorded pin, and what doesn't:

| Component | Pinned commit/version | Source |
|---|---|---|
| `mod-individual-progression` (ZhengPeiRu21) | `df1016444abcc21d025885282799ba76bebea627`, branch `master` | Recorded during compatibility testing — see [docs/COMPATIBILITY.md](COMPATIBILITY.md) |
| AzerothCore | Not pinned to an exact commit in current release records | — |
| `mod-ale` | Not pinned to an exact commit in current release records | — |
| `mod-playerbots` / Playerbots fork of AzerothCore | Not pinned to an exact commit — described only as "the documented AzerothCore/Playerbots environment used for this release" | See [docs/COMPATIBILITY.md](COMPATIBILITY.md) §3 |

**This is a real gap, not an oversight being papered over.** If you need to
reproduce Echoes' tested environment exactly rather than approximately,
open an issue — closing this gap (recording exact commits at the next
certification pass) is worth doing, but no hash is invented here to fill it.

## 4. DML Reference Environment

Echoes has been extensively tested in a Dad's MMO Lab-style environment —
AzerothCore running in Docker/WSL2 with a split runtime layout (the
installer's `--lua-root`/`--config-root` flags exist specifically to support
this). **Echoes is not an official Dad's MMO Lab project, is not endorsed by
Dad's MMO Lab, and is not maintained by the DML project** — this is a
compatibility statement about what Echoes has been tested against, nothing
more.

If you want to reproduce a setup close to one of Echoes' main test
environments from scratch, Dad's MMO Lab publishes a public
[AzerothCore + Playerbots WotLK guide](https://github.com/DadsMmoLab/dads-mmo-lab/blob/main/guides/wow-wotlk/README.md)
that clones the same `mod-playerbots/azerothcore-wotlk` and
`mod-playerbots/mod-playerbots` repositories listed in §2 above. You are not
required to use DML — any AzerothCore 3.3.5a environment with `mod-ale`
built in works.

## 5. Required vs. Optional Dependencies

| Dependency | Required? | Why |
|---|---|---|
| AzerothCore 3.3.5a source checkout | Required | Echoes ships as a source module, not a binary |
| `mod-ale` | Required | Echoes' entire server-side Lua system (`lua_scripts/`) runs on it |
| MySQL/MariaDB | Required | Echoes' own schema and item rows |
| `mod-playerbots` | Optional | `mod-echoes-playerbots` self-gates to an inert no-op without it |
| Docker/WSL split layout support | Optional | Only relevant for DML-style or similar split deployments |

## 6. Client Requirements

WoW 3.3.5a, build 12340, enUS. A clean/unmodified copy — see
[This Is Not a Repack](../README.md#this-is-not-a-repack) in the README for
the full explanation of what Echoes does and doesn't add to a client.

## 7. What Is NOT Required

- Any `mod-eluna` fork — `mod-ale` is the tested dependency
- Playerbots, in any form, unless you want that specific integration
- A modified `Wow.exe` or full redistributed client
- AzerothCore binaries — Echoes tests against a source build

## 8. Reproduction Notes

Reproducing Echoes' tested environment *closely* is straightforward: clone
`azerothcore/azerothcore-wotlk`, add `azerothcore/mod-ale`, follow
[INSTALL.md](../INSTALL.md). Reproducing it *exactly* (byte-identical
commits) is only possible where §3 above lists a pin — for everything else,
"upstream/reference project" is the accurate description, not a claim of
exact pin equivalence.

## 9. Fork/Version Caveats

AzerothCore, `mod-ale`, and Playerbots all have active development and
multiple forks in the ecosystem. A combination that works today does not
guarantee a later commit — to either Echoes' dependencies or to Echoes
itself — behaves identically. See
[Version / Fork Caveat](COMPATIBILITY.md#8-version--fork-caveat) in
docs/COMPATIBILITY.md for the same caveat as it applies to third-party
module compatibility specifically.
