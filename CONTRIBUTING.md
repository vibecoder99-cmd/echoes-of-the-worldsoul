# Contributing

Echoes of the Worldsoul is a small open-source project. Contributions are
welcome; the bar is reasonable, not enterprise-grade.

## Bug Reports / Compatibility Reports

Open a [GitHub Issue](https://github.com/vibecoder99-cmd/echoes-of-the-worldsoul/issues/new/choose)
using the appropriate template. Include:

- Echoes version (release tag or commit hash)
- AzerothCore revision
- Eluna/`mod-ale` version
- Operating system
- Whether you used the installer or a manual install, and single-root or
  split Docker/DML-style layout
- Whether Playerbots is present
- Client build
- Relevant logs (worldserver, Lua, SQL, or client errors) and exact
  reproduction steps

**Never paste database passwords or other credentials into an issue.**

## Feature Requests

Open an Issue or start a [Discussion](https://github.com/vibecoder99-cmd/echoes-of-the-worldsoul/discussions)
if you're not sure it's fully formed yet. Explain the player-facing
behavior you want, not just an implementation idea.

## Pull Requests

- Keep PRs scoped to one change. A bug fix doesn't need surrounding
  cleanup; a small feature doesn't need a new abstraction layer.
- If you're touching `installer/`, run the existing regression tests
  (`installer/tests/`) against a disposable MySQL instance before
  submitting — never against a production database.
- If you're touching gameplay Lua, run the relevant `#aptest` suite
  in-game before submitting.
- Describe what changed and why in the PR description, not just what.

## Questions

Use [Discussions](https://github.com/vibecoder99-cmd/echoes-of-the-worldsoul/discussions)
for "will this work for me," "how do I configure X," and general
questions. Use Issues for actual bugs and compatibility reports.
