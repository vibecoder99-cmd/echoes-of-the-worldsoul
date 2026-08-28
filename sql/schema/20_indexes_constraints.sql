-- ============================================================
-- Echoes of the Worldsoul -- 20_indexes_constraints.sql
-- Tracked E2j16 installer package.
-- Target: acore_characters. Idempotent via information_schema guard.
--
-- All primary keys and the one proven secondary index (ap_mastery_spend.
-- idx_guid) are already declared inline in 10_base_schema.sql's CREATE
-- statements, so on a true fresh install this file is a no-op safety net.
-- It exists to make a rerun against a partially-hand-built database safe:
-- if ap_mastery_spend exists but was created without idx_guid, this adds
-- it without erroring.
--
-- No foreign keys: every current CREATE statement in 10_base_schema.sql
-- (reconciled against live Lua read/write call sites) agrees there are no
-- cross-table FK constraints anywhere in the Echoes schema, including
-- `ap_dissolution_pending`; GUID/entry references are validated in Lua,
-- not enforced by the database.
-- ============================================================

SET @idx_exists = (
    SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'ap_mastery_spend'
      AND INDEX_NAME = 'idx_guid'
);

SET @ddl = IF(@idx_exists = 0,
    'ALTER TABLE `ap_mastery_spend` ADD KEY `idx_guid` (`guid`)',
    'SELECT ''idx_guid already present, skipped'''
);

PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
