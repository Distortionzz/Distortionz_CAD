-- =====================================================================
--  Distortionz CAD — schema. Run once via oxmysql.
--  Citizen/vehicle data is read live from `players` / `player_vehicles`;
--  only CAD-owned records are stored here.
-- =====================================================================

CREATE TABLE IF NOT EXISTS `distortionz_cad_charges` (
    `id`         INT(11) NOT NULL AUTO_INCREMENT,
    `citizenid`  VARCHAR(50) NOT NULL,
    `name`       VARCHAR(120) DEFAULT NULL,
    `charges`    LONGTEXT DEFAULT NULL,            -- JSON array of {label,fine,months}
    `total_fine` INT(11) NOT NULL DEFAULT 0,
    `total_jail` INT(11) NOT NULL DEFAULT 0,
    `notes`      TEXT DEFAULT NULL,
    `officer`    VARCHAR(120) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `distortionz_cad_warrants` (
    `id`         INT(11) NOT NULL AUTO_INCREMENT,
    `citizenid`  VARCHAR(50) NOT NULL,
    `name`       VARCHAR(120) DEFAULT NULL,
    `reason`     TEXT DEFAULT NULL,
    `status`     VARCHAR(16) NOT NULL DEFAULT 'active',  -- active | served
    `officer`    VARCHAR(120) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`),
    KEY `status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `distortionz_cad_bolos` (
    `id`         INT(11) NOT NULL AUTO_INCREMENT,
    `type`       VARCHAR(16) NOT NULL DEFAULT 'Person',
    `title`      VARCHAR(160) DEFAULT NULL,
    `details`    TEXT DEFAULT NULL,
    `reference`  VARCHAR(60) DEFAULT NULL,          -- plate or citizenid (optional)
    `status`     VARCHAR(16) NOT NULL DEFAULT 'active',
    `officer`    VARCHAR(120) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`),
    KEY `status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `distortionz_cad_reports` (
    `id`         INT(11) NOT NULL AUTO_INCREMENT,
    `type`       VARCHAR(32) NOT NULL DEFAULT 'Incident',
    `title`      VARCHAR(200) DEFAULT NULL,
    `narrative`  LONGTEXT DEFAULT NULL,
    `involved`   LONGTEXT DEFAULT NULL,             -- JSON array of names/cids
    `author`     VARCHAR(120) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`),
    KEY `type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dispatch call history. Active calls live in memory; when a call is
-- Resolved or Dismissed it is written here permanently (never deleted).
CREATE TABLE IF NOT EXISTS `distortionz_cad_calls` (
    `id`          INT(11) NOT NULL AUTO_INCREMENT,
    `code`        VARCHAR(24) DEFAULT NULL,
    `title`       VARCHAR(200) DEFAULT NULL,
    `location`    VARCHAR(160) DEFAULT NULL,
    `coords`      TEXT DEFAULT NULL,                -- JSON {x,y,z} or NULL
    `priority`    INT(11) NOT NULL DEFAULT 2,
    `source`      VARCHAR(60) DEFAULT NULL,
    `outcome`     VARCHAR(16) NOT NULL DEFAULT 'resolved',  -- resolved | dismissed
    `officer`     VARCHAR(120) DEFAULT NULL,        -- who cleared it
    `opened_at`   TIMESTAMP NULL DEFAULT NULL,
    `created_at`  TIMESTAMP NOT NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`),
    KEY `outcome` (`outcome`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
