# Echoes of the Worldsoul 2.1.7

This installer-only hotfix prevents an archive-installed `mod-ale` from being
mistaken for its parent AzerothCore Git checkout. Independent ALE clones are
identified by their own repository root and commit. Archive sources are
accepted only when exact fingerprints of both compatibility-patch preimages
match the certified snapshot. Modified or unknown sources remain fail-closed.

The installer now reports unsupported Python versions explicitly and explains
how to invoke the PowerShell wrapper. There are no gameplay, schema, save,
progression, balance, or item-data changes.
