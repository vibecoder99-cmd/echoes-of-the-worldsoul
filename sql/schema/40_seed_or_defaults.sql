-- ============================================================
-- Echoes of the Worldsoul -- 40_seed_or_defaults.sql
-- Tracked E2j16 installer package.
-- Target: acore_characters. Idempotent (INSERT ... ON DUPLICATE KEY
-- UPDATE, matching the conflict pattern already used throughout the
-- current Lua package).
--
-- No player-specific data, no test rows, no GM diagnostic rows.
-- The only "default" content this package requires is the
-- schema-version stamp. Inactive scaffolds are not created by this
-- installer, so they get no seed rows here either.
--
-- Version stamp: tracks AP.VERSION (ap_core.lua), the single public
-- version per the E2J13b versioning model, not an internal migration
-- counter.
-- ============================================================

INSERT INTO `ap_schema_version` (`id`, `version`)
VALUES (1, '2.1.4')
ON DUPLICATE KEY UPDATE
    `version`    = VALUES(`version`),
    `applied_at` = CURRENT_TIMESTAMP;
