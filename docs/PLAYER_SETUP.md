# Player Setup

This page is for **players joining an Echoes-enabled server** — not for
server owners. If you're setting Echoes up on your own server, see
[INSTALL.md](../INSTALL.md) instead.

## What you need

1. Your own compatible **WoW 3.3.5a (build 12340)** client.
2. The small Echoes client package from the server you're joining:
   - `EchoesOfTheWorldsoulBridge` (the Client Companion AddOn)
   - `patch-E.MPQ` (custom item data)
3. That server's realmlist/address.

## Where the files go

- **`patch-E.MPQ`** → your WoW client's `Data\` folder, next to the game's
  own `.MPQ` files:

  ```
  Data\patch-E.MPQ
  ```

- **The AddOn folder** → your client's AddOns directory:

  ```
  Interface\AddOns\EchoesOfTheWorldsoulBridge\
  ```

  (i.e. the whole `EchoesOfTheWorldsoulBridge` folder goes inside
  `Interface\AddOns\`, not its individual files loose.)

## Pointing your client at the server

Edit your client's `realmlist.wtf` (in the client's root folder) to contain
the address the server owner gave you, for example:

```
set realmlist logon.example.com
```

The exact address depends on the server you're joining — ask whoever runs
it if you don't have it already. This project doesn't run a server itself
and can't provide one.

## Launching

Start the client, log in, select your realm, and enable the AddOn at the
character-select AddOns screen if it isn't already checked.

---

## Troubleshooting

**AddOn doesn't appear at character select.**
Confirm the whole `EchoesOfTheWorldsoulBridge` folder (not just some files
from inside it) is directly under `Interface\AddOns\`, and that you
restarted the client after copying it in.

**AddOn shows as "out of date."**
Enable **Load out of date AddOns** at the character-select AddOns screen.
This is a normal WoW client setting, not specific to Echoes.

**Custom items show as question marks.**
`patch-E.MPQ` isn't in your `Data\` folder, or the client wasn't restarted
after adding it. Confirm the file is present and try again; if it's still
wrong, ask the server owner for a fresh copy — client packages are
per-server.

**`Error #132` after adding `patch-E.MPQ`.**
This usually means the file you received doesn't match a clean version of
your client, or got corrupted in transfer. Ask the server owner for a
fresh copy rather than trying to repair it yourself.

**Wrong client build / can't connect at all.**
You need WoW **3.3.5a, build 12340** specifically — other 3.3.5 builds or
other expansions will not work with an AzerothCore-based server. This is a
server-wide requirement, not an Echoes-specific one.

For anything not covered here, ask on the server you're playing on, or see
the general [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md) (which also
covers server-side issues, if you end up needing that context).
