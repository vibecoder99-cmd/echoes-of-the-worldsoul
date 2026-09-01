-- ============================================================
-- Echoes of the Worldsoul -- 10_base_schema.sql
-- Tracked E2j16 installer package. Target: acore_characters.
-- Idempotent: CREATE TABLE IF NOT EXISTS throughout. Safe to rerun.
-- No DROP/TRUNCATE. No player data.
--
-- Provenance: ported from env/backups/e2f1/20260715T184148-0700/package/sql/
-- (design-only E2f1 phase), reconciled against the current live Lua
-- runtime contract (env/dist/lua_scripts/ap04_db.lua REQUIRED_TABLES /
-- REQUIRED_COLUMNS as of AP.VERSION 1.7.1) before being brought under
-- tracked source. Full reconciliation trail:
-- docs/distribution/E2J16-CURRENT-SCHEMA-RECONCILIATION.md
--
-- Scope: the 18 tables the current runtime actually requires (17 tables
-- from the E2f1 design + `ap_dissolution_pending`, added post-E2f1 by the
-- E2j5h Dissolution transaction-safety work and never before brought into
-- any tracked installer package). Inactive scaffolds and zero-consumer
-- legacy tables are intentionally NOT created here -- see the
-- reconciliation record for the full exclusion list carried forward
-- unchanged from E2f1's Question 7 resolution.
-- ============================================================

-- ------------------------------------------------------------
-- CORE ATTUNEMENT
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `ap_item_attune` (
    `guid`       INT UNSIGNED NOT NULL,
    `item_entry` INT UNSIGNED NOT NULL,
    `progress`   INT UNSIGNED NOT NULL DEFAULT 0,
    `attuned`    TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`guid`, `item_entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ap_item_snapshot` (
    `guid`       INT UNSIGNED     NOT NULL,
    `item_entry` INT UNSIGNED     NOT NULL,
    `quality`    TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `str`        FLOAT            NOT NULL DEFAULT 0,
    `agi`        FLOAT            NOT NULL DEFAULT 0,
    `sta`        FLOAT            NOT NULL DEFAULT 0,
    `int`        FLOAT            NOT NULL DEFAULT 0,
    `spi`        FLOAT            NOT NULL DEFAULT 0,
    `armor`      FLOAT            NOT NULL DEFAULT 0,
    `weapon_dps` FLOAT            NOT NULL DEFAULT 0,
    PRIMARY KEY (`guid`, `item_entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- ESSENCE AND MASTERY
-- ap_mastery includes rate_*/rack_slots from initial CREATE: the native
-- runtime installer's 3-column CREATE is a known-stale subset, not the
-- target shape for a fresh install (unchanged from E2f1 Question 1/3).
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `ap_mastery` (
    `guid`        INT UNSIGNED     NOT NULL,
    `aether`      BIGINT UNSIGNED  NOT NULL DEFAULT 0,
    `mastery`     INT UNSIGNED     NOT NULL DEFAULT 0,
    `rate_xp`     FLOAT            NOT NULL DEFAULT 1,
    `rate_aether` FLOAT            NOT NULL DEFAULT 1,
    `rate_boss`   FLOAT            NOT NULL DEFAULT 1,
    `rack_slots`  TINYINT UNSIGNED NOT NULL DEFAULT 3,
    `chaos_enabled` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ap_mastery_spend` (
    `id`     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `guid`   INT UNSIGNED NOT NULL,
    `amount` INT UNSIGNED NOT NULL DEFAULT 0,
    `ts`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_guid` (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ap_slot_mastery` (
    `guid` INT UNSIGNED     NOT NULL,
    `slot` TINYINT UNSIGNED NOT NULL,
    `xp`   BIGINT UNSIGNED  NOT NULL DEFAULT 0,
    PRIMARY KEY (`guid`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ap_talents` (
    `guid`       INT UNSIGNED     NOT NULL,
    `stat_index` TINYINT UNSIGNED NOT NULL,
    `rank`       TINYINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`guid`, `stat_index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- THE CRUCIBLE (AETHER SINKS)
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `ap_aether_sinks` (
    `account_id` INT UNSIGNED NOT NULL,
    `category`   VARCHAR(32)  NOT NULL,
    `invested`   INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`account_id`, `category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ap_sink_allocation` (
    `guid`       INT UNSIGNED NOT NULL,
    `category`   VARCHAR(32)  NOT NULL,
    `allocation` FLOAT        NOT NULL DEFAULT 0,
    PRIMARY KEY (`guid`, `category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- LEGACY FORGE
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `ap_dissolved_items` (
    `account_id` INT UNSIGNED NOT NULL,
    `item_entry` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`account_id`, `item_entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ap_residue` (
    `account_id` INT UNSIGNED NOT NULL,
    `amount`     INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- `ap_dissolution_pending` -- added post-E2f1 by the E2j5h Stage 4
-- Dissolution transaction-safety work (Option C: durable two-phase
-- pending record). Never previously brought into any tracked installer
-- package; column shape derived directly from the current live
-- read/write call sites in ap_forge.lua and ap_tests.lua (see the
-- reconciliation record -- no historical SQL provenance exists for this
-- table because it postdates every prior SQL package snapshot).
CREATE TABLE IF NOT EXISTS `ap_dissolution_pending` (
    `guid`               INT UNSIGNED NOT NULL,
    `account_id`         INT UNSIGNED NOT NULL,
    `item_entry`         INT UNSIGNED NOT NULL,
    `item_instance_guid` INT UNSIGNED NOT NULL DEFAULT 0,
    `quality`            TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `essence_reward`     INT UNSIGNED NOT NULL DEFAULT 0,
    `gold_reward`        INT UNSIGNED NOT NULL DEFAULT 0,
    `residue_reward`     INT UNSIGNED NOT NULL DEFAULT 0,
    `status`             VARCHAR(20)  NOT NULL DEFAULT 'PENDING_REMOVAL',
    PRIMARY KEY (`guid`, `item_entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- ATTUNEMENT RACK
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `ap_rack` (
    `guid`         INT UNSIGNED NOT NULL,
    `slot_index`   TINYINT      NOT NULL,
    `item_entry`   INT UNSIGNED NOT NULL DEFAULT 0,
    `item_name`    VARCHAR(64)  NOT NULL DEFAULT '',
    `item_quality` TINYINT      NOT NULL DEFAULT 1,
    PRIMARY KEY (`guid`, `slot_index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- RESONANT DROPS
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `ap_resonant_drops` (
    `account_id` INT UNSIGNED NOT NULL,
    `item_entry` INT UNSIGNED NOT NULL,
    `drop_count` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`account_id`, `item_entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- VISAGE
-- Base 7 columns only here. Tier columns (primary_tier_selected,
-- secondary_tier_selected) are applied in 30_versioned_migrations.sql,
-- so a fresh install ends up with all 9 columns after 00->90 completes.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `ap_visage` (
    `guid`                INT UNSIGNED NOT NULL,
    `primary_theme`       VARCHAR(32)  NOT NULL DEFAULT 'worldsoul',
    `primary_enabled`     TINYINT      NOT NULL DEFAULT 1,
    `secondary_theme`     VARCHAR(32)  NOT NULL DEFAULT 'worldsoul',
    `secondary_enabled`   TINYINT      NOT NULL DEFAULT 1,
    `flash_enabled`       TINYINT      NOT NULL DEFAULT 1,
    `chat_flavor_enabled` TINYINT      NOT NULL DEFAULT 1,
    PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- QUEST TRACKING
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `ap_quest_rewarded` (
    `guid`     INT UNSIGNED NOT NULL,
    `quest_id` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`guid`, `quest_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ap_aether_milestones` (
    `account_id`     INT UNSIGNED NOT NULL,
    `milestone_type` VARCHAR(32)  NOT NULL,
    `milestone_id`   INT UNSIGNED NOT NULL,
    PRIMARY KEY (`account_id`, `milestone_type`, `milestone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- SESSION STATE
-- Base 3 columns only here. Threat columns (threat_level, threat_momentum,
-- threat_debt_kills, threat_debt_mult) are applied in
-- 30_versioned_migrations.sql, matching native production's own
-- guarded-ALTER pattern (ap_events.lua EnsureThreatSchema()).
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `ap_session_state` (
    `guid`        INT UNSIGNED NOT NULL,
    `clean_exit`  TINYINT(1)   NOT NULL DEFAULT 0,
    `last_update` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- AURALAB (GM-locked diagnostic subsystem; zero gameplay dependency)
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `ap_aura_test_results` (
    `guid`      INT UNSIGNED NOT NULL,
    `spell_id`  INT UNSIGNED NOT NULL,
    `theme`     VARCHAR(32)  NOT NULL DEFAULT '',
    `tier`      TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `result`    VARCHAR(16)  NOT NULL DEFAULT 'UNTESTED',
    `notes`     VARCHAR(255) NOT NULL DEFAULT '',
    `tested_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`guid`, `spell_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- SCHEMA VERSION LEDGER
-- Single-row marker, not a growing migration-history log. Row is
-- stamped by 40_seed_or_defaults.sql, read by 90_validation.sql, and
-- consulted by the guarded migration in 30_versioned_migrations.sql.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `ap_schema_version` (
    `id`         TINYINT UNSIGNED NOT NULL,
    `version`    VARCHAR(16)      NOT NULL,
    `applied_at` TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
