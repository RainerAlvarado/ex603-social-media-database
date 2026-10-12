-- ============================================================
-- EX603 Assignment 3, Task 3.2: Find the bug
-- Theme: Social Media   Database: ex603_data (provided social.sql)
-- Nullable column used: likes.removal_reason ("nullable by design").
-- The dataset already contains NULLs there, so none were inserted.
-- ============================================================

-- ------------------------------------------------------------
-- PART A: The rows that vanished
-- ------------------------------------------------------------

-- 3.2A-1  BROKEN. "Every reaction that was not removed as spam."
--         Looks exhaustive, but a row with no removal reason compares
--         NULL <> 'Spam detected', which is UNKNOWN, so WHERE drops it.
--         Requirement: inequality predicate on a nullable column.
SELECT COUNT(*) AS not_spam_broken
FROM likes
WHERE removal_reason <> 'Spam detected';

-- 3.2A-2  The rows the query above silently omitted: reactions with no
--         removal reason at all.
--         Requirement: count the omitted rows.
SELECT COUNT(*) AS silently_omitted
FROM likes
WHERE removal_reason IS NULL;

-- 3.2A-3  The predicate and its opposite, next to the table total.
--         If the filter were exhaustive, the first two would add up to
--         the third. They do not: the gap is the count from 3.2A-2.
--         Requirement: show the counts do not sum to the table total.
SELECT
  (SELECT COUNT(*) FROM likes WHERE removal_reason <> 'Spam detected') AS not_spam_broken,
  (SELECT COUNT(*) FROM likes WHERE removal_reason = 'Spam detected')  AS spam,
  (SELECT COUNT(*) FROM likes)                                         AS table_total,
  (SELECT COUNT(*) FROM likes WHERE removal_reason IS NULL)            AS silently_omitted;

-- 3.2A-4  REPAIR with an explicit IS NULL condition. Returns what was
--         intended: every reaction that was not removed as spam.
--         Requirement: repair using IS NULL.
SELECT COUNT(*) AS not_spam_repaired
FROM likes
WHERE removal_reason <> 'Spam detected'
   OR removal_reason IS NULL;

-- 3.2A-5  The same repair written with COALESCE.
--         Requirement: repair using COALESCE.
SELECT COUNT(*) AS not_spam_repaired
FROM likes
WHERE COALESCE(removal_reason, 'No reason provided') <> 'Spam detected';

-- 3.2A-6  After the repair the two halves account for the whole table.
SELECT
  (SELECT COUNT(*) FROM likes
    WHERE removal_reason <> 'Spam detected' OR removal_reason IS NULL) AS not_spam_repaired,
  (SELECT COUNT(*) FROM likes WHERE removal_reason = 'Spam detected')  AS spam,
  (SELECT COUNT(*) FROM likes)                                         AS table_total;

-- ------------------------------------------------------------
-- PART B: The alias that did not exist yet
-- ------------------------------------------------------------

-- 3.2B-1  BROKEN ON PURPOSE. "Reactions where the user stayed longer
--         than 30 seconds." WHERE is evaluated before SELECT, so the
--         alias dwell_seconds does not exist yet.
--         Verbatim error from PostgreSQL 18 (pgAdmin 4 Messages tab):
--           ERROR:  column "dwell_seconds" does not exist
--           LINE 5: WHERE dwell_seconds > 30
--                         ^
--
--           SQL state: 42703
--           Character: 73
--         Left commented out so this file runs end to end. To reproduce
--         for the screenshot, paste the six lines below, without the
--         leading dashes, into a blank Query Tool tab and run them.
-- SELECT
--   like_id,
--   dwell_ms / 1000.0 AS dwell_seconds
-- FROM likes
-- WHERE dwell_seconds > 30
-- ORDER BY dwell_seconds DESC;

-- 3.2B-2  REWRITE 1: repeat the expression in WHERE. ORDER BY runs
--         after SELECT, so the alias is fine there.
--         Requirement: correct rewrite repeating the expression.
SELECT
  like_id,
  dwell_ms / 1000.0 AS dwell_seconds
FROM likes
WHERE dwell_ms / 1000.0 > 30
ORDER BY dwell_seconds DESC, like_id ASC;

-- 3.2B-3  REWRITE 2: compute the value in a CTE so the alias becomes a
--         real column that the outer WHERE can see.
--         Requirement: correct rewrite using a CTE.
WITH reaction_dwell AS (
  SELECT
    like_id,
    dwell_ms / 1000.0 AS dwell_seconds
  FROM likes
)
SELECT
  like_id,
  dwell_seconds
FROM reaction_dwell
WHERE dwell_seconds > 30
ORDER BY dwell_seconds DESC, like_id ASC;
