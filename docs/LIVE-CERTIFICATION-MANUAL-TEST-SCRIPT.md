# Live Certification — Manual Client Test Script

This covers the remaining client-side steps of the Final Live Certification
Pass — the parts that require a graphical WoW client, a live login, and
reading in-game chat/UI, none of which this session can automate. Everything
else (package-equivalent server build, DML/generic installer walkthroughs,
README/INSTALL literal test, mpyq fallback) was run headlessly and is
recorded separately in `docs/COMPATIBILITY-ATTACK-DEFECT-LEDGER.md`.

## Client authority

- **`C:\Dad's MMO Lab Test WoW Client\`** — the authoritative current DML
  target for this certification. Use this client for everything below.
- **`C:\AzerothCore Client\`** — historical/alternate client, non-
  authoritative for current DML certification. Not used in this script.

Environment facts gathered before writing this script (read-only, no
mutation performed):

- The authoritative client's existing `Data\patch-4.MPQ` is **confirmed
  genuinely Echoes-owned**: SHA-256
  `2a9c38e589226d7c3ff84ef218e4a2d001801fcc9cf0e9252e6652ddcbc8bb4c`,
  positively identified via `installer/core/mpq_conflict.py`'s
  `identify_legacy_echoes_patch4()` (byte-exact match on both custom item
  records — confirmed against this real file, not just synthetic test
  fixtures). This is already a known-good payload; the remaining question
  is whether the installer's migration path correctly repackages it as
  `patch-E.MPQ`, not whether a fresh one can be rebuilt from a vanilla
  `Item.dbc` (that detour is out of scope for this pass).
- A live, healthy production Docker stack (`ac-authserver`, `ac-worldserver`,
  `ac-database`) is already running (44+ hours up). Use this existing server
  for the steps below — do not stand up a second live server. (A separate,
  disposable, from-scratch package-equivalent server was already built and
  boot-tested headlessly; that is independent of this client work.)
- Current AddOn version at time of writing: `1.5.9`
  (`client_addon/EchoesOfTheWorldsoulBridge/EchoesOfTheWorldsoulBridge.toc`).
- `#aptest forge` is recorded as **user-reported live PASS** (exact counts
  not captured, not independently witnessed this session) — see the ledger.
  It does not need to be rerun for current certification scope. Step 5
  below is now optional, only if you want to capture exact evidence for the
  record.

---

## Step 0 — Backups (do this first, before touching anything)

```powershell
Copy-Item "C:\Dad's MMO Lab Test WoW Client\Data\patch-4.MPQ" `
  "C:\Dad's MMO Lab Test WoW Client\Data\patch-4.MPQ.pre-live-cert-backup"
Copy-Item -Recurse "C:\Dad's MMO Lab Test WoW Client\Interface\AddOns\EchoesOfTheWorldsoulBridge" `
  "C:\Dad's MMO Lab Test WoW Client\Interface\AddOns\EchoesOfTheWorldsoulBridge.pre-live-cert-backup"
Get-ChildItem "C:\Dad's MMO Lab Test WoW Client\Data\patch*.MPQ" | Select Name, Length
```

Record the full `Data\patch*.MPQ` inventory output somewhere — that's your
"before" state for comparison after migration.

---

## Step 1 — Migrate patch-4.MPQ to patch-E.MPQ via the installer

Run the installer's `install` (or `upgrade`, if a manifest already exists on
this deployment) command with `--client-root` pointed at the authoritative
client:

```powershell
installer\bin\echoes.ps1 install `
  --azerothcore-root <your real AzerothCore root> `
  --mysql-user <user> --mysql-password <password> `
  --characters-database acore_characters --world-database acore_world `
  --client-root "C:\Dad's MMO Lab Test WoW Client"
```

This exercises the actual migration path: the installer identifies the
existing `patch-4.MPQ` via the same byte-exact fingerprint check confirmed
above, backs it up, and produces `patch-E.MPQ` from that already-proven
payload — no vanilla `Item.dbc` extraction needed.

Confirm after this step:

- [ ] `Data\patch-E.MPQ` exists
- [ ] `Data\patch-4.MPQ` — migrated/backed up (check the installer's backup
      location, e.g. `echoes-installer-backups/`)
- [ ] Record the final `Data\patch*.MPQ` inventory again for comparison
- [ ] Record `patch-E.MPQ`'s SHA-256:
      `Get-FileHash "C:\Dad's MMO Lab Test WoW Client\Data\patch-E.MPQ" -Algorithm SHA256`

---

## Step 2 — Launch and log in

Launch `Wow.exe` from `C:\Dad's MMO Lab Test WoW Client\` and connect to the
existing running production server.

Record:

- [ ] Exact client build shown at the login screen (expect `3.3.5.12340`)
- [ ] Client launches without crashing
- [ ] Login succeeds
- [ ] **No `Error #132`** (the classic "corrupted/mismatched DBC" error — if
      it appears, patch-E.MPQ has a problem; stop and report the exact error
      text rather than continuing)
- [ ] No DBC-related startup failure of any other kind
- [ ] AddOns screen shows `EchoesOfTheWorldsoulBridge` enabled (enable "Load
      out of date AddOns" if it's greyed out)

---

## Step 3 — Item resolution (900010 / 900011)

On a GM account:

```
.additem 900010
.additem 900011
```

- [ ] Item 900010 (**Worldsoul Echo Fragment**) shows a real name and icon,
      not a question mark
- [ ] Item 900011 (**Worldsoul Residue**) shows a real name and icon
- [ ] Tooltip text/display data looks correct for both

---

## Step 4 — Patch load order (optional, secondary priority)

The release-critical requirement is just that patch-E loads (already
covered in Step 2). Skip this unless convenient — a benign D/E/F load-order
fixture test against a full backup, or just accept the existing documented
precedent as sufficient, per the original authorization.

---

## Step 5 — Forge live regression (optional, evidence-capture only)

Already recorded as user-reported PASS; not required to close current
certification. Only rerun if you want exact captured numbers for the
record:

```
#aptest forge
```

If you do run it, report total/pass/fail counts and whether the
`OnForgeDissolve` / `itemEntry = itemEntry` case specifically passes.

---

## Step 6 — Client Companion route check

Not a visual/polish review — just confirm each panel opens and populates
without a Lua error:

- [ ] `#ap` — Dashboard opens
- [ ] Progression opens
- [ ] Talents opens
- [ ] World Threat opens
- [ ] Crucible opens
- [ ] `#ap rack` — Rack opens
- [ ] `#ap forge` — Forge opens
- [ ] Visage opens
- [ ] Codex/Search opens
- [ ] Settings/Accessibility opens
- [ ] State values (Essence, Mastery, etc.) show real numbers, not
      blank/zero-by-default-error
- [ ] No missing-asset errors (question-mark textures, etc.)
- [ ] No Lua errors in the client error frame (enable `Interface Options ->
      Display Lua Errors` if you don't already have an error-catching addon)

---

## Step 7 — One non-destructive server-backed action

Pick one reversible action and confirm the full round trip
(request → protocol → server → response → client) actually works:

- [ ] Suggested: open Visage and preview a theme (should not commit/spend
      anything) — OR request current Rack/Crucible state via the panel
      (a read-only "what do I currently have" view) — OR any other
      preview/state-request action that doesn't consume Essence, dissolve
      an item, or otherwise change persistent state.
- [ ] Record which action you used and what happened.

---

## Reporting back

For each step above, come back with: pass/fail per checkbox and any exact
error text. I'll fold the results into
`docs/COMPATIBILITY-ATTACK-DEFECT-LEDGER.md` and the final live-certification
report, and only then evaluate the overall verdict for this authorization.

Do not proceed to a live production-affecting change (e.g. deleting the
backed-up `patch-4.MPQ`, or overwriting the live AddOn permanently) until
we've confirmed everything above — the backups from Step 0 exist specifically
so this is reversible if something looks wrong.
