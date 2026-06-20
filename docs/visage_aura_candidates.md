# Visage Aura Candidate Spell IDs

Test each with `#ap testaura <id>` in-game. Remove with `#ap clearaura <id>`.

## Testing Protocol

1. `.reload eluna`
2. `#ap testaura <id>`
3. Move character for 10 seconds
4. Note: follows player? persists? any gameplay effect?
5. `#ap clearaura <id>` to remove
6. Record result below

## Result Key

- **GOOD** = follows player, persists, no gameplay effect, cosmetic only
- **GROUND** = visual stays at cast position, does not follow
- **FLICKER** = appears briefly then vanishes
- **NONE** = no visible effect at all
- **HARMFUL** = deals damage, buffs stats, or has gameplay impact
- **CRASH** = causes client/server issue

---

## Batch 1: Known Persistent Visual Auras (WotLK 3.3.5a)

These are spells known to have persistent aura visuals on players.

### Subtle / Holy / Worldsoul theme candidates

| ID    | Name / Description              | Result | Notes |
|-------|--------------------------------|--------|-------|
| 32567 | Plague Cloud (green particles) | | |
| 36032 | Arcane Charge (purple glow)    | | |
| 45846 | Aura of Protection (gold glow) | | |
| 32770 | Enchanting visual (subtle sparkles) | | |

### Void / Shadow theme candidates

| ID    | Name / Description              | Result | Notes |
|-------|--------------------------------|--------|-------|
| 34709 | Shadow visual (dark effect)    | | |
| 32455 | Shadow aura (dark particles)   | | |
| 30531 | Shadow Inferno (dark fire)     | | |
| 36153 | Shadow Sear visual             | | |

### Fire / Infernal theme candidates

| ID    | Name / Description              | Result | Notes |
|-------|--------------------------------|--------|-------|
| 19626 | Fire Shield (fire particles)   | | |
| 30927 | Burning Speed (fire aura)      | | |
| 37764 | Fire visual (orange glow)      | | |
| 36006 | Flame visual aura              | | |

### Ethereal / Arcane theme candidates

| ID    | Name / Description              | Result | Notes |
|-------|--------------------------------|--------|-------|
| 44816 | Arcane visual aura             | | |
| 36513 | Arcane Brilliance visual       | | |
| 44867 | Spectral visual (translucent)  | | |
| 36032 | Arcane Charge (purple glow)    | | |

### Nature / Verdant theme candidates

| ID    | Name / Description              | Result | Notes |
|-------|--------------------------------|--------|-------|
| 34246 | Thorns visual (green)          | | |
| 41190 | Nature visual aura             | | |
| 39485 | Green/nature particles         | | |
| 35194 | Nature channel visual          | | |

---

## Batch 2: Additional Candidates (if Batch 1 is insufficient)

| ID    | Name / Description              | Result | Notes |
|-------|--------------------------------|--------|-------|
| 30166 | Shadow Grasp visual            | | |
| 37816 | (currently used void T2)       | | |
| 34427 | (currently used ethereal T5)   | | |
| 22578 | (currently used void T1)       | | |
| 33070 | (currently used void T3)       | | |
| 39490 | (currently used void T4)       | | |
| 42050 | (currently used verdant T5)    | | |

Test the current IDs too - some may actually work, just not all of them.

---

## How to Report

For each ID tested, fill in the Result column and Notes:

Example:
```
| 32567 | Plague Cloud | GOOD | green particles follow player, persist through movement and relog |
| 34709 | Shadow visual | FLICKER | dark flash for 1 second then gone |
| 19626 | Fire Shield | HARMFUL | applies fire damage to nearby mobs |
```

After enough GOOD results (need 25 total: 5 per theme, 5 themes),
the ThemeSpells table will be updated with verified IDs.
