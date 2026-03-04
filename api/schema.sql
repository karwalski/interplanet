-- InterPlanet — database schema migration
-- Run once against the sky_colours database.
-- Compatible with MariaDB 10.6+ / MySQL 8.0+.

-- ─────────────────────────────────────────────────────────────────────────────
-- Existing table (created by earlier deployment — shown for reference)
-- ─────────────────────────────────────────────────────────────────────────────

-- CREATE TABLE IF NOT EXISTS sky_configs (
--   id         INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
--   code       CHAR(6)      NOT NULL UNIQUE,
--   config     MEDIUMTEXT   NOT NULL,
--   views      INT UNSIGNED NOT NULL DEFAULT 0,
--   created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
--   expires_at DATETIME     NOT NULL,
--   INDEX idx_expires (expires_at)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────────────────────
-- LTX Sessions  (Story 20.2 — api/ltx.php POST ?action=session)
-- Stores validated SessionPlan JSON keyed by deterministic plan_id.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS ltx_sessions (
  id         INT UNSIGNED  NOT NULL AUTO_INCREMENT PRIMARY KEY,
  plan_id    VARCHAR(100)  NOT NULL UNIQUE COMMENT 'LTX-YYYYMMDD-HOST-NODE-v2-XXXXXXXX',
  plan_json  MEDIUMTEXT    NOT NULL COMMENT 'Full SessionPlan as received',
  total_min  SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Total meeting duration in minutes',
  views      INT UNSIGNED  NOT NULL DEFAULT 0,
  created_at DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='LTX session plans stored for retrieval and ICS generation';

-- ─────────────────────────────────────────────────────────────────────────────
-- LTX Feedback  (Story 20.3 — api/ltx.php POST ?action=feedback)
-- Post-meeting telemetry for ML scheduling optimisation pipeline.
-- No PII required — node names should be location labels.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS ltx_feedback (
  id             INT UNSIGNED  NOT NULL AUTO_INCREMENT PRIMARY KEY,
  plan_id        VARCHAR(100)  NULL      COMMENT 'FK reference to ltx_sessions.plan_id (nullable — ad-hoc sessions)',
  session_title  VARCHAR(200)  NULL,
  mode           ENUM('LTX-LIVE','LTX-RELAY','LTX-ASYNC') NULL,
  actual_start   DATETIME      NULL      COMMENT 'UTC actual meeting start',
  actual_end     DATETIME      NULL      COMMENT 'UTC actual meeting end',
  nodes_json     TEXT          NULL      COMMENT 'JSON array of {name,location,delay_s}',
  segments_json  TEXT          NULL      COMMENT 'JSON array of {type,completed}',
  outcome        ENUM('completed','partial','aborted','unknown') NOT NULL DEFAULT 'unknown',
  satisfaction   TINYINT UNSIGNED NULL   COMMENT '1–5 participant-reported satisfaction',
  relay_used     TINYINT(1)    NOT NULL DEFAULT 0 COMMENT 'True if LTX-RELAY fallback was triggered',
  signal_issues  TINYINT(1)    NOT NULL DEFAULT 0 COMMENT 'True if signal disruption reported',
  notes          VARCHAR(1000) NULL      COMMENT 'Free-text post-meeting notes',
  raw_json       MEDIUMTEXT    NULL      COMMENT 'Full payload as received (for ML ingestion)',
  created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_plan    (plan_id),
  INDEX idx_outcome (outcome),
  INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Post-meeting telemetry for ML scheduling optimisation';

-- ─────────────────────────────────────────────────────────────────────────────
-- Future: ML feature store view
-- Aggregates feedback into per-node-pair statistics for scheduling model.
-- ─────────────────────────────────────────────────────────────────────────────

-- CREATE VIEW ltx_node_pair_stats AS
-- SELECT
--   JSON_UNQUOTE(JSON_EXTRACT(n1.value, '$.location')) AS loc_a,
--   JSON_UNQUOTE(JSON_EXTRACT(n2.value, '$.location')) AS loc_b,
--   mode,
--   COUNT(*)                                           AS sessions,
--   AVG(satisfaction)                                  AS avg_satisfaction,
--   SUM(relay_used)                                    AS relay_count,
--   SUM(signal_issues)                                 AS signal_issue_count,
--   SUM(outcome = 'completed')                         AS completed_count,
--   HOUR(actual_start)                                 AS start_hour_utc
-- FROM ltx_feedback
-- WHERE JSON_LENGTH(nodes_json) >= 2
-- GROUP BY loc_a, loc_b, mode, start_hour_utc;
