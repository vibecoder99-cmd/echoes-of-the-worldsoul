# Echoes of the Worldsoul 2.1.6

This installer, documentation, and compatibility-diagnostics hotfix corrects
the public ALE setup order. Operators must dry-run and explicitly apply the
bundled revision-locked `CharDBDirectExecute` patch before building
worldserver. Discovery and verification now identify the exact capability and
guarded-write readiness, and purchase failures no longer imply that a healthy
database is offline.

There are no gameplay, schema, save, client-item-data, or progression changes.
