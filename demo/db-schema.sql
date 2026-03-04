-- Sky Colours — share configuration table
-- Run once against the 'sky_colours' database after creating it:
--   CREATE DATABASE sky_colours CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
--   CREATE USER 'sky_user'@'localhost' IDENTIFIED BY 'changeme';
--   GRANT SELECT, INSERT, UPDATE ON sky_colours.* TO 'sky_user'@'localhost';
--   FLUSH PRIVILEGES;

CREATE TABLE IF NOT EXISTS `sky_configs` (
    `id`         INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    `code`       CHAR(6)         NOT NULL             COMMENT '6-char base62 share code',
    `config`     MEDIUMTEXT      NOT NULL             COMMENT 'JSON-encoded config blob',
    `created_at` DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at` DATETIME        NOT NULL             COMMENT 'Auto-expires 30 days after creation',
    `views`      INT UNSIGNED    NOT NULL DEFAULT 0   COMMENT 'Access counter',
    PRIMARY KEY (`id`),
    UNIQUE  KEY `uq_code`    (`code`),
    KEY         `idx_expires` (`expires_at`)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Shared sky-colours view configurations';

-- Optional: scheduled cleanup (run via cron or MySQL event scheduler)
-- DELETE FROM sky_configs WHERE expires_at < NOW();
