-- ============================================================
-- Echoes of the Worldsoul -- 30_versioned_migrations.sql
-- Tracked E2j16 installer package.
-- Target: acore_characters. Idempotent via information_schema guard,
-- matching native production's own guarded-ALTER pattern
-- (ap_events.lua EnsureThreatSchema / ap_visage.lua MigrateVisageDb /
-- ap_core.lua addColumnIfMissing), reproduced here as a one-time
-- installer step rather than a runtime Lua side effect.
--
-- Reconciled against the current live REQUIRED_COLUMNS contract in
-- ap04_db.lua: no ALTER beyond the four migrations below is required.
-- `ap_dissolution_pending` (the only schema addition post-E2f1) is a new
-- table, created directly in 10_base_schema.sql -- it needs no ALTER
-- migration here.
--
-- Each block: metadata-guarded ADD COLUMN. No block runs a bare ALTER;
-- every one checks information_schema.COLUMNS first.
-- ============================================================

DELIMITER $$

-- ---- ap_session_state: 4 threat columns (World Threat v2) ----
CREATE PROCEDURE `_ap_migrate_001`()
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap_session_state'
                     AND COLUMN_NAME = 'threat_level') THEN
        ALTER TABLE `ap_session_state` ADD COLUMN `threat_level` TINYINT UNSIGNED NOT NULL DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap_session_state'
                     AND COLUMN_NAME = 'threat_momentum') THEN
        ALTER TABLE `ap_session_state` ADD COLUMN `threat_momentum` FLOAT NOT NULL DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap_session_state'
                     AND COLUMN_NAME = 'threat_debt_kills') THEN
        ALTER TABLE `ap_session_state` ADD COLUMN `threat_debt_kills` SMALLINT UNSIGNED NOT NULL DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap_session_state'
                     AND COLUMN_NAME = 'threat_debt_mult') THEN
        ALTER TABLE `ap_session_state` ADD COLUMN `threat_debt_mult` FLOAT NOT NULL DEFAULT 1;
    END IF;
END$$

-- ---- ap_visage: 2 tier columns (Tier 6) ----
CREATE PROCEDURE `_ap_migrate_002`()
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap_visage'
                     AND COLUMN_NAME = 'primary_tier_selected') THEN
        ALTER TABLE `ap_visage` ADD COLUMN `primary_tier_selected` TINYINT UNSIGNED NOT NULL DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap_visage'
                     AND COLUMN_NAME = 'secondary_tier_selected') THEN
        ALTER TABLE `ap_visage` ADD COLUMN `secondary_tier_selected` TINYINT UNSIGNED NOT NULL DEFAULT 0;
    END IF;
END$$

-- ---- ap_mastery: rate_*/rack_slots backfill guard ----
-- On a true fresh install this is a no-op (10_base_schema.sql already
-- creates the full 7-column table). Retained for an EXISTING pre-1.5.0-era
-- database whose ap_mastery only has the native runtime installer's
-- leaner 3-column shape.
CREATE PROCEDURE `_ap_migrate_003`()
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap_mastery'
                     AND COLUMN_NAME = 'rate_xp') THEN
        ALTER TABLE `ap_mastery` ADD COLUMN `rate_xp` FLOAT NOT NULL DEFAULT 1;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap_mastery'
                     AND COLUMN_NAME = 'rate_aether') THEN
        ALTER TABLE `ap_mastery` ADD COLUMN `rate_aether` FLOAT NOT NULL DEFAULT 1;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap_mastery'
                     AND COLUMN_NAME = 'rate_boss') THEN
        ALTER TABLE `ap_mastery` ADD COLUMN `rate_boss` FLOAT NOT NULL DEFAULT 1;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap_mastery'
                     AND COLUMN_NAME = 'rack_slots') THEN
        ALTER TABLE `ap_mastery` ADD COLUMN `rack_slots` TINYINT UNSIGNED NOT NULL DEFAULT 3;
    END IF;
END$$

-- ---- AuraLab spell-ID corrections ----
-- RESERVED, NOT part of the fresh-install path. Only meaningful against
-- an EXISTING ap_aura_test_results table that already contains rows for
-- these specific spell_id values from a pre-fix GM test session. On any
-- table with no matching rows (including every fresh install) each
-- UPDATE is a no-op by construction. Guarded additionally by
-- ap_schema_version so it executes at most once even if this file reruns.
CREATE PROCEDURE `_ap_migrate_004_auralab_fix`()
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.TABLES
               WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap_aura_test_results')
       AND NOT EXISTS (SELECT 1 FROM `ap_schema_version` WHERE `id` = 1 AND `version` >= '1.6.1-m004') THEN
        UPDATE `ap_aura_test_results` SET `theme`='infernal', `tier`=3, `result`='T3' WHERE `spell_id`=62300;
        UPDATE `ap_aura_test_results` SET `theme`='worldsoul', `tier`=4, `result`='T4' WHERE `spell_id`=46933;
        UPDATE `ap_aura_test_results` SET `tier`=2, `result`='T2' WHERE `spell_id`=49411;
        UPDATE `ap_aura_test_results` SET `tier`=2, `result`='T2' WHERE `spell_id`=44808;
    END IF;
END$$

DELIMITER ;

CALL `_ap_migrate_001`();
CALL `_ap_migrate_002`();
CALL `_ap_migrate_003`();

-- ap_schema_version is created in 10_base_schema.sql (schema, not data)
-- and stamped with its initial row in 40_seed_or_defaults.sql, which runs
-- immediately after this file -- so on a FRESH install, ap_schema_version
-- has no row yet the first time this file runs, and
-- `_ap_migrate_004_auralab_fix`'s guard condition correctly treats "no
-- matching version row" as "not yet applied" and still safely no-ops
-- (ap_aura_test_results is empty on a fresh install regardless). On a
-- rerun after 40 has stamped the version, the guard prevents re-applying
-- the fix a second time.
CALL `_ap_migrate_004_auralab_fix`();

DROP PROCEDURE `_ap_migrate_001`;
DROP PROCEDURE `_ap_migrate_002`;
DROP PROCEDURE `_ap_migrate_003`;
DROP PROCEDURE `_ap_migrate_004_auralab_fix`;
