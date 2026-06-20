-- ============================================================
-- Echoes of the Worldsoul -- Full Database Schema
-- Copyright (C) 2025-2026 vibecoder99 -- GPLv3
--
-- Target database : acore_characters
-- Safe to run on  : a fresh acore_characters (AzerothCore base
--                   schema already applied) OR an existing install
--                   (all statements use CREATE TABLE IF NOT EXISTS).
-- Idempotent      : yes -- running twice produces no errors and
--                   makes no changes to existing data.
--
-- Run order: this single file is self-contained. No splits needed;
-- none of these tables carry foreign-key constraints to each other.
-- ============================================================

-- ============================================================
-- CORE ATTUNEMENT TABLES
-- ============================================================

-- Per-character, per-item attunement progress and completion flag.
-- attuned=1 is permanent once set and is never cleared by the mod.
CREATE TABLE IF NOT EXISTS `ap_item_attune` (
    `guid`       INT UNSIGNED NOT NULL,
    `item_entry` INT UNSIGNED NOT NULL,
    `progress`   INT UNSIGNED NOT NULL DEFAULT 0,
    `attuned`    TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`guid`, `item_entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- Per-character, per-item stat snapshot captured at full attunement.
-- Stores the raw stats of the item at the moment it was fully attuned.
-- `int` is a reserved word but is safe as a column name when backtick-quoted.
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- ============================================================
-- ESSENCE AND MASTERY
-- ============================================================

-- Per-character Essence balance, mastery rank, personal gain rates,
-- and Attunement Rack slot capacity.
-- rate_* columns default to 1.0 (100% = normal rate).
-- rack_slots starts at 3 (minimum capacity).
CREATE TABLE IF NOT EXISTS `ap_mastery` (
    `guid`        INT UNSIGNED    NOT NULL,
    `aether`      BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `mastery`     INT UNSIGNED    NOT NULL DEFAULT 0,
    `rate_xp`     FLOAT           NOT NULL DEFAULT 1,
    `rate_aether` FLOAT           NOT NULL DEFAULT 1,
    `rate_boss`   FLOAT           NOT NULL DEFAULT 1,
    `rack_slots`  TINYINT         NOT NULL DEFAULT 3,
    PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- Audit log of Essence spend events (Mastery purchases).
-- Not required for gameplay; used for GM diagnostics and balance tuning.
CREATE TABLE IF NOT EXISTS `ap_mastery_spend` (
    `id`     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `guid`   INT UNSIGNED NOT NULL,
    `amount` INT UNSIGNED NOT NULL DEFAULT 0,
    `ts`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_guid` (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- Per-slot XP accumulation used by the slot multiplier formula.
CREATE TABLE IF NOT EXISTS `ap_slot_mastery` (
    `guid` INT UNSIGNED     NOT NULL,
    `slot` TINYINT UNSIGNED NOT NULL,
    `xp`   BIGINT UNSIGNED  NOT NULL DEFAULT 0,
    PRIMARY KEY (`guid`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- Unused talent/stat-index upgrade table (reserved for future use).
CREATE TABLE IF NOT EXISTS `ap_talents` (
    `guid`       INT UNSIGNED     NOT NULL,
    `stat_index` TINYINT UNSIGNED NOT NULL,
    `rank`       TINYINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`guid`, `stat_index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- ============================================================
-- THE CRUCIBLE (AETHER SINKS)
-- ============================================================

-- Per-account Essence investment in each of the 18 sink categories.
-- category values match the AP.SinkDefs keys in ap_sinks.lua.
CREATE TABLE IF NOT EXISTS `ap_aether_sinks` (
    `account_id` INT UNSIGNED NOT NULL,
    `category`   VARCHAR(32)  NOT NULL,
    `invested`   INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`account_id`, `category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- Per-character per-sink allocation weight (unused in current release;
-- reserved for a future multi-sink split investment feature).
CREATE TABLE IF NOT EXISTS `ap_sink_allocation` (
    `guid`       INT UNSIGNED NOT NULL,
    `category`   VARCHAR(32)  NOT NULL,
    `allocation` FLOAT        NOT NULL DEFAULT 0,
    PRIMARY KEY (`guid`, `category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- ============================================================
-- LEGACY FORGE
-- ============================================================

-- Per-account record of dissolved item entries.
-- Each entry can be dissolved once per account; this table enforces that.
-- The dissolution ordering in ap_forge.lua depends on this table
-- being written BEFORE any rewards are granted.
CREATE TABLE IF NOT EXISTS `ap_dissolved_items` (
    `account_id` INT UNSIGNED NOT NULL,
    `item_entry` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`account_id`, `item_entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- Per-account Worldsoul Residue balance (the currency earned via dissolution).
-- Physical item counts are reconciled against this ledger on login.
CREATE TABLE IF NOT EXISTS `ap_residue` (
    `account_id` INT UNSIGNED NOT NULL,
    `amount`     INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- ============================================================
-- ATTUNEMENT RACK
-- ============================================================

-- Per-character rack slot contents. Items are tracked by entry only;
-- physical possession is verified at add time but not enforced ongoing.
-- item_entry=0 means the slot is empty.
CREATE TABLE IF NOT EXISTS `ap_rack` (
    `guid`         INT UNSIGNED NOT NULL,
    `slot_index`   TINYINT      NOT NULL,
    `item_entry`   INT UNSIGNED NOT NULL DEFAULT 0,
    `item_name`    VARCHAR(64)  NOT NULL DEFAULT '',
    `item_quality` TINYINT      NOT NULL DEFAULT 1,
    PRIMARY KEY (`guid`, `slot_index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- ============================================================
-- RESONANT DROPS
-- ============================================================

-- Per-account drop count per item entry for Legacy Surge detection.
-- drop_count >= 4 on the 4th+ duplicate triggers the 3x Essence bonus.
CREATE TABLE IF NOT EXISTS `ap_resonant_drops` (
    `account_id` INT UNSIGNED NOT NULL,
    `item_entry` INT UNSIGNED NOT NULL,
    `drop_count` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`account_id`, `item_entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- ============================================================
-- VISAGE
-- ============================================================

-- Per-character Visage settings: active theme, aura toggle, flash toggle.
-- Default theme is 'worldsoul'; valid themes defined in ap_visage.lua.
CREATE TABLE IF NOT EXISTS `ap_visage` (
    `guid`                INT UNSIGNED NOT NULL,
    `primary_theme`       VARCHAR(32)  NOT NULL DEFAULT 'worldsoul',
    `primary_enabled`     TINYINT      NOT NULL DEFAULT 1,
    `secondary_theme`     VARCHAR(32)  NOT NULL DEFAULT 'worldsoul',
    `secondary_enabled`   TINYINT      NOT NULL DEFAULT 1,
    `flash_enabled`       TINYINT      NOT NULL DEFAULT 1,
    `chat_flavor_enabled` TINYINT      NOT NULL DEFAULT 1,
    PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- ============================================================
-- PVP
-- ============================================================

-- BG objective Essence reward definitions (currently unpopulated;
-- Eluna hooks for BG objectives are not available in this build).
-- Included so the table exists if the feature is enabled in future.
CREATE TABLE IF NOT EXISTS `ap_bg_objectives` (
    `id`             INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    `bg_type_id`     TINYINT UNSIGNED NOT NULL,
    `objective_id`   INT UNSIGNED  NOT NULL,
    `essence_reward` INT UNSIGNED  NOT NULL DEFAULT 25,
    `description`    VARCHAR(64)   DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `bg_obj_unique` (`bg_type_id`, `objective_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- ============================================================
-- MILESTONE SYSTEM
-- ============================================================

-- Milestone definition table (label + Essence reward per milestone ID).
CREATE TABLE IF NOT EXISTS `ap_milestone_defs` (
    `id`            INT UNSIGNED NOT NULL,
    `label`         VARCHAR(64)  NOT NULL DEFAULT '',
    `aether_reward` INT UNSIGNED NOT NULL DEFAULT 50,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- Per-character milestone completion records.
CREATE TABLE IF NOT EXISTS `ap_milestones` (
    `guid`         INT UNSIGNED NOT NULL,
    `milestone_id` INT UNSIGNED NOT NULL,
    `ts`           TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`guid`, `milestone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- Per-account one-time trigger records for tutorial messages,
-- dungeon conquest tracking, and other account-scoped milestones.
-- milestone_type examples: 'tutorial_first_attune', 'dungeon_conquest'
-- milestone_id: 1 for tutorial triggers; map ID for dungeon conquests.
CREATE TABLE IF NOT EXISTS `ap_aether_milestones` (
    `account_id`     INT UNSIGNED NOT NULL,
    `milestone_type` VARCHAR(32)  NOT NULL,
    `milestone_id`   INT UNSIGNED NOT NULL,
    PRIMARY KEY (`account_id`, `milestone_type`, `milestone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- ============================================================
-- ATTUNEMENT RATE PRESETS (ADMIN CONFIG)
-- ============================================================

-- Named rate presets for per-kill attunement configuration.
-- The active preset is selected via AP.Config in ap_core.lua.
-- Populated manually by the server admin; the mod reads from
-- AP.Config, not from this table at runtime.
CREATE TABLE IF NOT EXISTS `ap_attunements` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `preset`      VARCHAR(32)  NOT NULL,
    `perKillBase` INT          NOT NULL,
    `bonusBoss`   INT          NOT NULL,
    `capPerItem`  INT          NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_preset` (`preset`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- ============================================================
-- QUEST TRACKING
-- ============================================================

-- Per-character record of quests that have already granted Essence.
-- Prevents duplicate grants on quest replay/abandon-and-redo.
CREATE TABLE IF NOT EXISTS `ap_quest_rewarded` (
    `guid`     INT UNSIGNED NOT NULL,
    `quest_id` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`guid`, `quest_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- ============================================================
-- SESSION STATE (Residue reconciliation: clean-exit detection)
-- ============================================================

-- Written to on graceful logout (clean_exit=1). On login, if
-- clean_exit=0 or missing, the player crashed — preserve residue
-- snapshots. On server startup, all rows reset to clean_exit=0
-- to handle server crashes (no per-player logout fires).
CREATE TABLE IF NOT EXISTS `ap_session_state` (
    `guid`        INT UNSIGNED NOT NULL,
    `clean_exit`  TINYINT(1)   NOT NULL DEFAULT 0,
    `last_update` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- ============================================================
-- TELEMETRY (OPTIONAL)
-- ============================================================

-- Lightweight event log for server-side balance analysis.
-- Not required for gameplay. Can be safely left empty or truncated.
CREATE TABLE IF NOT EXISTS `ap_telemetry` (
    `id`    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `guid`  INT UNSIGNED    NOT NULL,
    `event` VARCHAR(32)     NOT NULL DEFAULT '',
    `value` FLOAT           NOT NULL DEFAULT 0,
    `ts`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_guid_event` (`guid`, `event`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
