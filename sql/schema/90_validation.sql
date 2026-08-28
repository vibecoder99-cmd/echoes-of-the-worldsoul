-- ============================================================
-- Echoes of the Worldsoul -- 90_validation.sql
-- Tracked E2j16 installer package. Read-only SELECT checks only --
-- no DDL/DML in this file. Run last, always.
--
-- Mirrors the metadata-only readiness gate the live Lua runtime already
-- implements (ap04_db.lua's 18-table/column REQUIRED_TABLES/
-- REQUIRED_COLUMNS readiness check), so a passing result here should
-- exactly predict a passing runtime readiness check after the Lua
-- package loads.
-- ============================================================

-- 1. All 18 current tables exist.
SELECT TABLE_NAME,
       CASE WHEN COUNT(*) = 1 THEN 'OK' ELSE 'MISSING' END AS status
FROM information_schema.TABLES
RIGHT JOIN (
    SELECT 'ap_mastery' AS t UNION ALL SELECT 'ap_item_attune'
    UNION ALL SELECT 'ap_item_snapshot' UNION ALL SELECT 'ap_session_state'
    UNION ALL SELECT 'ap_slot_mastery' UNION ALL SELECT 'ap_talents'
    UNION ALL SELECT 'ap_quest_rewarded' UNION ALL SELECT 'ap_aether_milestones'
    UNION ALL SELECT 'ap_aether_sinks' UNION ALL SELECT 'ap_resonant_drops'
    UNION ALL SELECT 'ap_rack' UNION ALL SELECT 'ap_mastery_spend'
    UNION ALL SELECT 'ap_visage' UNION ALL SELECT 'ap_dissolved_items'
    UNION ALL SELECT 'ap_residue' UNION ALL SELECT 'ap_sink_allocation'
    UNION ALL SELECT 'ap_aura_test_results' UNION ALL SELECT 'ap_dissolution_pending'
) AS required ON TABLE_SCHEMA = DATABASE() AND TABLE_NAME = required.t
GROUP BY TABLE_NAME;

-- 2. Every column this package installs actually exists with the
--    expected type (spot-check rack_slots, rate_*, the 4 threat columns,
--    the 2 tier columns, every column of ap_dissolution_pending, and
--    every other current-mandatory/selected table).
SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND (
    (TABLE_NAME = 'ap_mastery' AND COLUMN_NAME IN ('rate_xp','rate_aether','rate_boss','rack_slots'))
    OR (TABLE_NAME = 'ap_session_state' AND COLUMN_NAME IN ('threat_level','threat_momentum','threat_debt_kills','threat_debt_mult'))
    OR (TABLE_NAME = 'ap_visage' AND COLUMN_NAME IN ('primary_tier_selected','secondary_tier_selected'))
    OR TABLE_NAME IN ('ap_aether_sinks','ap_resonant_drops','ap_rack','ap_dissolved_items','ap_residue','ap_sink_allocation','ap_dissolution_pending')
  )
ORDER BY TABLE_NAME, COLUMN_NAME;

-- 3. Primary/unique keys match the resolved design.
SELECT TABLE_NAME, INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columns, NON_UNIQUE
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN (
    'ap_mastery','ap_item_attune','ap_item_snapshot','ap_session_state',
    'ap_slot_mastery','ap_talents','ap_quest_rewarded','ap_aether_milestones',
    'ap_aether_sinks','ap_resonant_drops','ap_rack','ap_mastery_spend',
    'ap_visage','ap_dissolved_items','ap_residue','ap_sink_allocation',
    'ap_aura_test_results','ap_dissolution_pending'
  )
GROUP BY TABLE_NAME, INDEX_NAME, NON_UNIQUE
ORDER BY TABLE_NAME, INDEX_NAME;

-- 4. Engine and character-database ownership for every table.
SELECT TABLE_NAME, ENGINE, TABLE_COLLATION
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME LIKE 'ap\_%'
ORDER BY TABLE_NAME;

-- 5. Confirm no inactive-scaffold or zero-consumer table was created
--    by mistake (should return zero rows).
SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN (
    'ap_milestone_defs','ap_milestones','ap_telemetry',
    'ap_bg_objectives','ap_attunements','ap_aether_ledger',
    'ap_world_threat','ap_relic_drops','ap_visage_library','ap_slot_talents'
  );

-- 6. Schema version stamp present and current.
SELECT `id`, `version`, `applied_at` FROM `ap_schema_version` WHERE `id` = 1;

-- 7. Row-count sanity (should be 0 for every table on a genuine fresh
--    install; nonzero indicates this is not actually a fresh install and
--    the migration path, not the fresh-install path, should have been
--    used).
SELECT 'ap_mastery' AS tbl, COUNT(*) AS row_count FROM `ap_mastery`
UNION ALL SELECT 'ap_item_attune', COUNT(*) FROM `ap_item_attune`
UNION ALL SELECT 'ap_session_state', COUNT(*) FROM `ap_session_state`
UNION ALL SELECT 'ap_dissolution_pending', COUNT(*) FROM `ap_dissolution_pending`;
