-- RowsAffected vs matched rows — minimal reproduction
-- Run:  mysql -u root -p < examples/repro.sql
--
-- Actual output, MySQL 8.4.13 (Ubuntu 26.04, WSL), 2026-11-18:
--   | affected_rows |  ->  0        <- same value written again
--   | matched_rows  |  ->  1        <- the row is definitely there
--   | affected_rows |  ->  1        <- a real change
--   ERROR 1062 (23000) at line 36: Duplicate entry '42' for key 'sites.uk_account_id'
--
-- Note the table-qualified key name in 8.4; older versions print it unqualified.
--
-- If stmt 1 reports 1 instead of 0, your session has CLIENT_FOUND_ROWS
-- enabled (dsn ?clientFoundRows=true) — that changes the whole meaning.

DROP DATABASE IF EXISTS rowsaffected_repro;
CREATE DATABASE rowsaffected_repro;
USE rowsaffected_repro;

CREATE TABLE sites (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  account_id  BIGINT UNSIGNED NOT NULL,
  site_domain VARCHAR(255)    NOT NULL,
  UNIQUE KEY uk_account_id (account_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO sites (account_id, site_domain) VALUES (42, 'example.com');

-- 1) same value written again: MySQL considers the row unchanged
UPDATE sites SET site_domain = 'example.com' WHERE account_id = 42;
SELECT ROW_COUNT() AS affected_rows;   -- 0
SELECT COUNT(*)    AS matched_rows FROM sites WHERE account_id = 42;  -- 1

-- 2) a real change does count
UPDATE sites SET site_domain = 'example.org' WHERE account_id = 42;
SELECT ROW_COUNT() AS affected_rows;   -- 1

-- 3) what the buggy "affected == 0 => INSERT" branch does next
INSERT INTO sites (account_id, site_domain) VALUES (42, 'example.org');
-- ERROR 1062 (23000): Duplicate entry '42' for key 'uk_account_id'
