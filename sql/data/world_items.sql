-- ============================================================
-- Echoes of the Worldsoul -- World Database Item Data
-- Copyright (C) 2025-2026 vibecoder99 -- GPLv3
--
-- Target database : acore_world
-- IMPORTANT: This is a SEPARATE database from the schema file.
--            Run sql/schema/00_preflight.sql through 90_validation.sql
--            against acore_characters first, then run this file
--            against acore_world.
--
-- These two item_template rows define the physical inventory items
-- used by the Legacy Forge and Resonant Drop systems.
--
-- Guarded and idempotent: absent rows are inserted; a pre-existing row
-- matching every field controlled below is accepted as-is; any
-- pre-existing row with a DIFFERENT value in a controlled field raises
-- SQLSTATE 45000 before either INSERT runs, so unexpected custom content
-- is never silently retained or overwritten. This replaces a plain
-- `INSERT IGNORE` used by earlier releases, which could not detect that
-- case.
-- ============================================================

DROP PROCEDURE IF EXISTS `echoes_apply_world_items`;
DELIMITER //
CREATE PROCEDURE `echoes_apply_world_items`()
BEGIN
    -- Entry 900010: Worldsoul Echo Fragment
    -- Granted when a player loots an item they have already fully attuned.
    -- Right-click to receive Essence + gold. Also disenchantable and vendorable.
    -- spellid_1=8690 enables the right-click "use" interaction.
    IF EXISTS (
        SELECT 1 FROM `item_template`
        WHERE `entry` = 900010 AND NOT (
            `class` <=> 15 AND `subclass` <=> 0 AND `SoundOverrideSubclass` <=> -1 AND
            `name` <=> 'Worldsoul Echo Fragment' AND `displayid` <=> 55243 AND
            `Quality` <=> 1 AND `BuyCount` <=> 1 AND `BuyPrice` <=> 0 AND
            `SellPrice` <=> 1 AND `InventoryType` <=> 0 AND
            `AllowableClass` <=> -1 AND `AllowableRace` <=> -1 AND
            `ItemLevel` <=> 1 AND `RequiredLevel` <=> 0 AND
            `stackable` <=> 1 AND `maxcount` <=> 0 AND
            `spellid_1` <=> 8690 AND `spelltrigger_1` <=> 0 AND
            `spellcharges_1` <=> 0 AND `spellcooldown_1` <=> -1 AND
            `spellcategory_1` <=> 0 AND `spellcategorycooldown_1` <=> -1 AND
            `spellid_2` <=> 0 AND `spellid_3` <=> 0 AND
            `spellid_4` <=> 0 AND `spellid_5` <=> 0 AND
            `delay` <=> 1000 AND `bonding` <=> 0 AND
            `description` <=> 'A fragment of a claimed echo. Right-click to absorb its power and receive Essence and gold. Can also be disenchanted or vendored.' AND
            `RequiredDisenchantSkill` <=> -1 AND `Material` <=> 0
        )
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Echoes world-item conflict: item_template entry 900010 differs from the expected Worldsoul Echo Fragment signature';
    END IF;

    -- Entry 900011: Worldsoul Residue
    -- Earned by dissolving fully-attuned items in the Legacy Forge.
    -- Stackable currency used to expand the Attunement Rack and for
    -- the Crucible Catalyst (10 Residue -> 5,000 Essence).
    IF EXISTS (
        SELECT 1 FROM `item_template`
        WHERE `entry` = 900011 AND NOT (
            `class` <=> 15 AND `subclass` <=> 0 AND `SoundOverrideSubclass` <=> -1 AND
            `name` <=> 'Worldsoul Residue' AND `displayid` <=> 55242 AND
            `Quality` <=> 3 AND `BuyCount` <=> 1 AND `BuyPrice` <=> 0 AND
            `SellPrice` <=> 1 AND `InventoryType` <=> 0 AND
            `AllowableClass` <=> -1 AND `AllowableRace` <=> -1 AND
            `ItemLevel` <=> 1 AND `RequiredLevel` <=> 0 AND
            `stackable` <=> 999 AND `maxcount` <=> 999 AND
            `spellid_1` <=> 0 AND `delay` <=> 1000 AND `bonding` <=> 0 AND
            `description` <=> 'A crystallized fragment of a claimed echo, returned to you by the Worldsoul. Bring these to the Legacy Forge.' AND
            `RequiredDisenchantSkill` <=> -1 AND `Material` <=> -1
        )
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Echoes world-item conflict: item_template entry 900011 differs from the expected Worldsoul Residue signature';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM `item_template` WHERE `entry` = 900010) THEN
        INSERT INTO `item_template`
            (`entry`, `class`, `subclass`, `SoundOverrideSubclass`, `name`,
             `displayid`, `Quality`, `BuyCount`, `BuyPrice`, `SellPrice`,
             `InventoryType`, `AllowableClass`, `AllowableRace`,
             `ItemLevel`, `RequiredLevel`, `stackable`, `maxcount`,
             `spellid_1`, `spelltrigger_1`, `spellcharges_1`,
             `spellcooldown_1`, `spellcategory_1`, `spellcategorycooldown_1`,
             `spellid_2`, `spellid_3`, `spellid_4`, `spellid_5`,
             `delay`, `bonding`, `description`, `RequiredDisenchantSkill`, `Material`)
        VALUES
            (900010, 15, 0, -1, 'Worldsoul Echo Fragment',
             55243, 1, 1, 0, 1, 0, -1, -1, 1, 0, 1, 0,
             8690, 0, 0, -1, 0, -1, 0, 0, 0, 0, 1000, 0,
             'A fragment of a claimed echo. Right-click to absorb its power and receive Essence and gold. Can also be disenchanted or vendored.',
             -1, 0);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM `item_template` WHERE `entry` = 900011) THEN
        INSERT INTO `item_template`
            (`entry`, `class`, `subclass`, `SoundOverrideSubclass`, `name`,
             `displayid`, `Quality`, `BuyCount`, `BuyPrice`, `SellPrice`,
             `InventoryType`, `AllowableClass`, `AllowableRace`,
             `ItemLevel`, `RequiredLevel`, `stackable`, `maxcount`,
             `spellid_1`, `delay`, `bonding`, `description`,
             `RequiredDisenchantSkill`, `Material`)
        VALUES
            (900011, 15, 0, -1, 'Worldsoul Residue',
             55242, 3, 1, 0, 1, 0, -1, -1, 1, 0, 999, 999,
             0, 1000, 0,
             'A crystallized fragment of a claimed echo, returned to you by the Worldsoul. Bring these to the Legacy Forge.',
             -1, -1);
    END IF;

    IF (SELECT COUNT(*) FROM `item_template` WHERE `entry` IN (900010, 900011)) <> 2 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Echoes world-item postflight failed: expected item_template rows were not both present';
    END IF;
END //
DELIMITER ;
CALL `echoes_apply_world_items`();
DROP PROCEDURE `echoes_apply_world_items`;
