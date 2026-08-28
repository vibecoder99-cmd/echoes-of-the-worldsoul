# Live Certification — Manual Client Test Script

This covers sections 2, 3, 4, 6, and 7 of the Final Live Certification Pass —
the parts that require a graphical WoW client, a live login, and reading
in-game chat/UI, none of which this session can automate. Everything else
(package-equivalent server build, DML/generic installer walkthroughs,
README/INSTALL literal test, mpyq fallback) was run headlessly and is
recorded separately in `docs/COMPATIBILITY-ATTACK-DEFECT-LEDGER.md`.

Environment facts gathered before writing this script (read-only, no
mutation performed):

- Two client copies exist on this machine: `C:\AzerothCore Client\` and
  `C:\Dad's MMO Lab Test WoW Client\`. **Both already have `patch-4.MPQ`
  installed and `EchoesOfTheWorldsoulBridge` present** — neither is a clean
  baseline. `C:\Dad's MMO Lab Test WoW Client\` additionally has an
  `EchoesOfTheWorldsoulBridge.pre-E2J15-backup-20260822-224745` folder,
  indicating it's the designated Echoes test client with prior test history.
  **Recommendation: use `C:\Dad's MMO Lab Test WoW Client\`** and leave
  `C:\AzerothCore Client\` alone as your other reference copy.
- The existing `Data\patch-4.MPQ` in both copies is **confirmed genuinely
  Echoes-owned**: SHA-256
  `2a9c38e589226d7c3ff84ef218e4a2d001801fcc9cf0e9252e6652ddcbc8bb4c`,
  positively identified via `installer/core/mpq_conflict.py`'s
  `identify_legacy_echoes_patch4()` (byte-exact match on both custom item
  records — confirmed against this real file, not just synthetic test
  fixtures). It is safe for the installer's legacy-migration path to convert
  it to `patch-E.MPQ`.
- **No genuinely vanilla `Item.dbc` was found on this machine** (neither
  client copy is unpatched, and no cached vanilla copy exists in the repo or
  user profile). Step 1 below covers extracting one.
- A live, healthy production Docker stack (`ac-authserver`, `ac-worldserver`,
  `ac-database`) is already running (44+ hours up). Per the authorization's
  section 13 ("do not touch production unnecessarily... use the existing
  healthy environment as valuable evidence"), **use this existing server for
  the client-side tests below** — do not stand up a second live server. (A
  separate, disposable, from-scratch package-equivalent server was already
  built and boot-tested headlessly for section 5; that is independent of
  this client work.)
- Current AddOn version at time of writing: `1.5.9`
  (`client_addon/EchoesOfTheWorldsoulBridge/EchoesOfTheWorldsoulBridge.toc`).

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
"before" state for comparison after installing patch-E.MPQ.

---

## Step 1 — Get a vanilla Item.dbc and build patch-E.MPQ

No vanilla `Item.dbc` is available on this machine, so extract one first
using an MPQ editor (e.g. Ladik's MPQ Editor):

1. Open `C:\Dad's MMO Lab Test WoW Client\Data\common.MPQ` (or
   `common-2.MPQ` — whichever contains `DBFilesClient\Item.dbc`; check both
   if unsure) in the MPQ editor.
2. Extract `DBFilesClient\Item.dbc` to somewhere like
   `C:\Users\felle\Desktop\Item_vanilla.dbc`.

   **Important:** `common.MPQ` is a base client archive, not one of the
   `patch-*.MPQ` files — it should not have been touched by any server
   patch, so this extraction should genuinely be vanilla. If in doubt,
   compare the extracted file's record count against the expected baseline
   below before proceeding.

3. Build the patch:

   ```powershell
   cd "C:\Users\felle\OneDrive\Desktop\echoes-of-the-worldsoul"
   python dbc_patch\build_patch_mpq.py "C:\Users\felle\Desktop\Item_vanilla.dbc" "C:\Users\felle\Desktop\echoes-patch-e-output"
   ```

4. Confirm the script's self-check output shows all 8 `[PASS]` lines and the
   expected before/after summary:

   ```
   Record count : 46,096  ->  46,098  (+2)
   File size    : 1,475,093 bytes  ->  1,475,157 bytes  (+64)
   ```

   If your input file's *starting* record count differs from 46,096, your
   `Item.dbc` was not actually vanilla (some other patch already modified
   it) — stop and get a cleaner source before continuing.

5. The output directory should contain a built MPQ. **Rename/save it as
   `patch-E.MPQ`** (not whatever default name the tool gives it, if any) and
   record its SHA-256:

   ```powershell
   Get-FileHash "C:\Users\felle\Desktop\echoes-patch-e-output\*.mpq" -Algorithm SHA256
   ```

---

## Step 2 — Install patch-E.MPQ and migrate the legacy patch-4.MPQ

Copy the new `patch-E.MPQ` into
`C:\Dad's MMO Lab Test WoW Client\Data\`. Leave the existing `patch-4.MPQ`
in place for now — do **not** delete it manually. (If you'd rather use the
installer's own migration path instead of a plain copy, run
`installer\bin\echoes.ps1 install ...` with `--client-root "C:\Dad's MMO Lab Test WoW Client"`
against your real AzerothCore root; it will detect the existing patch-4.MPQ,
verify it's Echoes' own via the same fingerprint check confirmed above, back
it up, and migrate automatically — this is the more realistic real-world
path and preferred if practical.)

Confirm after this step:

- [ ] `Data\patch-E.MPQ` exists
- [ ] `Data\patch-4.MPQ` — either still present (manual-copy path) or
      migrated/backed-up (installer path); record which happened
- [ ] Record the final `Data\patch*.MPQ` inventory again for comparison

---

## Step 3 — Launch and log in

Launch `Wow.exe` from `C:\Dad's MMO Lab Test WoW Client\` and connect to the
existing running production server.

Record:

- [ ] Exact client build shown at the login screen (expect `3.3.5.12340`)
- [ ] Client launches without crashing
- [ ] Login succeeds
- [ ] **No `Error #132`** (this is the classic "corrupted/mismatched DBC"
      error — if it appears, patch-E.MPQ has a problem, stop and report the
      exact error text rather than continuing)
- [ ] No DBC-related startup failure of any other kind
- [ ] AddOns screen shows `EchoesOfTheWorldsoulBridge` enabled (enable "Load
      out of date AddOns" if it's greyed out)

---

## Step 4 — Item resolution (900010 / 900011)

On a GM account:

```
.additem 900010
.additem 900011
```

- [ ] Item 900010 (**Worldsoul Echo Fragment**) shows a real name and icon,
      not a question mark
- [ ] Item 900011 (**Worldsoul Residue**) shows a real name and icon
- [ ] Tooltip text/display data looks correct for both
- [ ] No repeated `CMSG_ITEM_QUERY_SINGLE`-style retry behavior (if you have
      a way to observe client/server logs; if not, just note whether the
      item icon ever "settles" normally vs. stays perpetually blank)

---

## Step 5 — Patch load order (optional, secondary priority)

Per the authorization, exact D/E/F load-order proof is desirable but
secondary — the release-critical requirement is just that patch-E loads
(already covered in Step 3). Only attempt this if convenient:

- If you want to probe the relationship, you'd need benign, empty/no-op
  test MPQs named `patch-D.MPQ` and `patch-F.MPQ` to see whether client
  behavior changes — **do not do this against your real Data folder** without
  a full backup, since a malformed MPQ in the load chain can affect client
  boot. If this doesn't feel safe/practical right now, skip it and note
  "documented as externally/in-project supported, not independently
  re-verified this pass" — that's an accepted outcome per the authorization.

---

## Step 6 — Forge live regression

On a GM account, in-game:

```
#aptest forge
```

Record:

- [ ] Total tests run
- [ ] Pass count
- [ ] Fail count
- [ ] Specifically: does the `OnForgeDissolve` / `itemEntry = itemEntry`
      regression case show as passing? (Look for it by name in the output.)

If anything besides that specific case fails, stop and report the exact
failure text before treating certification as complete — per the
authorization, other Forge failures need investigation, not just a note.

---

## Step 7 — Client Companion route check

Not a visual/polish review — just confirm each panel opens and populates
without a Lua error:

- [ ] `#ap` — Dashboard opens
- [ ] Progression opens
- [ ] Talents opens
- [ ] World Threat opens
- [ ] Crucible opens
- [ ] `#ap rack` — Rack opens
- [ ] `#ap forge` — Forge opens (already touched in Step 6, but re-check
      panel-open behavior here)
- [ ] Visage opens
- [ ] Codex/Search opens
- [ ] Settings/Accessibility opens
- [ ] State values (Essence, Mastery, etc.) show real numbers, not
      blank/zero-by-default-error
- [ ] No missing-asset errors (question-mark textures, etc.)
- [ ] No Lua errors in the client error frame (enable `Interface Options ->
      Display Lua Errors` if you don't already have an error-catching addon)

---

## Step 8 — One non-destructive server-backed action

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

For each step above, come back with: pass/fail per checkbox, any exact
error text, and the `#aptest forge` numbers. I'll fold the results into
`docs/COMPATIBILITY-ATTACK-DEFECT-LEDGER.md` and the final live-certification
report, and only then evaluate the overall verdict for this authorization.

Do not proceed to a live production-affecting change (e.g. deleting the
backed-up `patch-4.MPQ`, or overwriting the live AddOn permanently) until
we've confirmed everything above — the backups from Step 0 exist specifically
so this is reversible if something looks wrong.
