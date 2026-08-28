-- ============================================================
-- Echoes of the Worldsoul -- 00_preflight.sql
-- Tracked E2j16 installer package. Read-only checks.
-- Target: acore_characters. Run this file first, always.
-- ============================================================

-- Confirm we are pointed at the correct database (fails loudly rather
-- than silently installing into the wrong schema).
SELECT
    DATABASE() AS current_database,
    CASE WHEN DATABASE() = 'acore_characters'
         THEN 'OK' ELSE 'FAIL: wrong target database' END AS db_check;

-- Confirm database-level charset/collation matches the installer's
-- assumption (utf8mb4 / utf8mb4_unicode_ci).
SELECT
    DEFAULT_CHARACTER_SET_NAME,
    DEFAULT_COLLATION_NAME,
    CASE WHEN DEFAULT_CHARACTER_SET_NAME = 'utf8mb4'
         THEN 'OK' ELSE 'WARN: unexpected default charset' END AS charset_check
FROM information_schema.SCHEMATA
WHERE SCHEMA_NAME = DATABASE();

-- Existing-install detection: does ap_schema_version already exist?
-- (0 rows = fresh install path; 1 row = existing-install migration path.)
SELECT COUNT(*) AS ap_schema_version_exists
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ap_schema_version';

-- Partial-install detection: count of current-required ap_ tables that
-- already exist. 0 = clean fresh install. 18 = fully installed already
-- (idempotent rerun). Any other number = partial install; STOP and
-- investigate manually before proceeding -- do not let 10_base_schema.sql
-- run blindly against a partial state without a human looking at this
-- count first.
SELECT COUNT(*) AS existing_current_table_count
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN (
    'ap_mastery','ap_item_attune','ap_item_snapshot','ap_session_state',
    'ap_slot_mastery','ap_talents','ap_quest_rewarded','ap_aether_milestones',
    'ap_aether_sinks','ap_resonant_drops','ap_rack','ap_mastery_spend',
    'ap_visage','ap_dissolved_items','ap_residue','ap_sink_allocation',
    'ap_aura_test_results','ap_dissolution_pending'
  );

-- Engine availability check (InnoDB required for every Echoes table).
SELECT ENGINE, SUPPORT FROM information_schema.ENGINES WHERE ENGINE = 'InnoDB';
