-- ============================================================
-- Echoes of the Worldsoul -- World Database Item Data
-- Copyright (C) 2025-2026 vibecoder99 -- GPLv3
--
-- Target database : acore_world
-- IMPORTANT: This is a SEPARATE database from the schema file.
--            Run full_schema.sql against acore_characters first,
--            then run this file against acore_world.
--
-- These two item_template rows define the physical inventory items
-- used by the Legacy Forge and Resonant Drop systems.
-- INSERT IGNORE is safe to run multiple times.
-- ============================================================

-- Entry 900010: Worldsoul Echo Fragment
-- Granted when a player loots an item they have already fully attuned.
-- Right-click to receive Essence + gold. Also disenchantable and vendorable.
-- spellid_1=8690 enables the right-click "use" interaction.
INSERT IGNORE INTO `item_template`
    (`entry`, `class`, `subclass`, `SoundOverrideSubclass`, `name`,
     `displayid`, `Quality`, `BuyCount`, `BuyPrice`, `SellPrice`,
     `InventoryType`, `AllowableClass`, `AllowableRace`,
     `ItemLevel`, `RequiredLevel`,
     `stackable`, `maxcount`,
     `spellid_1`, `spelltrigger_1`, `spellcharges_1`,
     `spellcooldown_1`, `spellcategory_1`, `spellcategorycooldown_1`,
     `spellid_2`, `spellid_3`, `spellid_4`, `spellid_5`,
     `delay`, `bonding`, `description`,
     `RequiredDisenchantSkill`, `Material`)
VALUES
    (900010, 15, 0, -1, 'Worldsoul Echo Fragment',
     55243, 1, 1, 0, 1,
     0, -1, -1,
     1, 0,
     1, 0,
     8690, 0, 0,
     -1, 0, -1,
     0, 0, 0, 0,
     1000, 0,
     'A fragment of a claimed echo. Right-click to absorb its power and receive Essence and gold. Can also be disenchanted or vendored.',
     -1, 0);

-- Entry 900011: Worldsoul Residue
-- Earned by dissolving fully-attuned items in the Legacy Forge.
-- Stackable currency used to expand the Attunement Rack and for
-- the Crucible Catalyst (10 Residue -> 5,000 Essence).
INSERT IGNORE INTO `item_template`
    (`entry`, `class`, `subclass`, `SoundOverrideSubclass`, `name`,
     `displayid`, `Quality`, `BuyCount`, `BuyPrice`, `SellPrice`,
     `InventoryType`, `AllowableClass`, `AllowableRace`,
     `ItemLevel`, `RequiredLevel`,
     `stackable`, `maxcount`,
     `spellid_1`, `delay`, `bonding`,
     `description`, `RequiredDisenchantSkill`, `Material`)
VALUES
    (900011, 15, 0, -1, 'Worldsoul Residue',
     55242, 3, 1, 0, 1,
     0, -1, -1,
     1, 0,
     999, 999,
     0, 1000, 0,
     'A crystallized fragment of a claimed echo, returned to you by the Worldsoul. Bring these to the Legacy Forge.',
     -1, -1);
