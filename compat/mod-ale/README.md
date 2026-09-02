# mod-ALE synchronous character-write compatibility

Echoes' guarded economic transitions require a synchronous mutation followed
by authoritative read-back. `CharDBExecute` queues work asynchronously, while
`CharDBQuery` is a query/result API and must not be repurposed for writes.

`0001-expose-chardb-directexecute.patch` adds only:

- the `CharDBDirectExecute` global registration; and
- a matching Lua function that formats arguments using ALE's existing
  convention, calls `CharacterDatabase.DirectExecute(query)`, and returns no
  Lua results.

It is tested against official `azerothcore/mod-ale` `master` commit
`9eeb1f3c47a81291548874fa4be2f4cde35e2ec3`. Its canonical-LF SHA-256 is
`87cbd3d08d8ae5a73d4ef7c7e176bdc342d4676c15eb2e4aef9f2ab8a1547b82`.

The installer dry-runs and checksum-verifies this artifact before use and
requires the operator's explicit `--apply` consent. It refuses other source
revisions. Applying the patch does not rebuild or restart AzerothCore.

## Proposed upstream contribution

Subject: `feat(lua): expose synchronous character database execute helper`

Rationale: expose AzerothCore's existing synchronous character-database
one-way execution primitive to Lua for callers that must verify a completed
mutation immediately. The API mirrors the existing `CharDBExecute` parsing and
formatting contract, changes no existing global, and contains no Echoes-specific
logic. Maintainer review is recommended before submission; the tracked patch is
ready to be proposed as-is.
