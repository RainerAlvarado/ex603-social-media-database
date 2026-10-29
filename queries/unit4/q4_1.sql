-- ============================================================
-- EX603 Assignment 4, Task 4.1: Measure the platform
-- Theme: Social Media   Database: ex603_data (provided social.sql)
-- Roles: actor = users, producer = posts, event = likes (reactions)
-- Metric: likes.dwell_ms (viewing time before the like, in ms)
-- Failure (carried over from Unit 3): a reaction removed as spam,
--   i.e. reaction_status = 'removed' AND removal_reason = 'Spam detected'
-- Region: likes.client_country (where the reaction came from)
-- ============================================================

-- 4.1-1  Platform-wide baseline. Across every reaction: how many are
--        there, what is the total, average, minimum and maximum dwell
--        time, and how many distinct users produced them?
--        Requirement: COUNT, SUM, AVG, MIN, MAX, COUNT(DISTINCT) over
--        the whole event table, no GROUP BY.
-- Finding: 200 reactions from 30 distinct users on 13 distinct posts.
--          Average dwell is 18,141 ms, max 70,860 ms, MIN is 0. Dwell
--          should never be zero for a counted like, so the zero needs
--          investigating (see 4.1-1b).
SELECT
  COUNT(*)                     AS total_reactions,
  COUNT(dwell_ms)              AS reactions_with_dwell,
  SUM(dwell_ms)                AS total_dwell_ms,
  ROUND(AVG(dwell_ms), 2)      AS avg_dwell_ms,
  MIN(dwell_ms)                AS min_dwell_ms,
  MAX(dwell_ms)                AS max_dwell_ms,
  COUNT(DISTINCT user_id)      AS distinct_actors,
  COUNT(DISTINCT post_id)      AS distinct_producers
FROM likes;

-- 4.1-1b  Data-quality follow-up on the zero minimum. Which status do
--         the zero-dwell reactions have?
--         Requirement: review results carefully; investigate a minimum
--         that should not be possible.
-- Finding: all 34 zero-dwell rows are removed reactions, and every
--          removed reaction has dwell 0. Removal wipes the metric, so
--          AVG(dwell_ms) over all rows is pulled down by rows that no
--          longer carry a real measurement.
SELECT
  reaction_status,
  COUNT(*)               AS reactions,
  MIN(dwell_ms)          AS min_dwell_ms,
  MAX(dwell_ms)          AS max_dwell_ms,
  ROUND(AVG(dwell_ms))   AS avg_dwell_ms
FROM likes
GROUP BY reaction_status
ORDER BY reaction_status;

-- 4.1-2  Per producer: how many reactions did each post receive, and
--        what is its average dwell time? Most active post first.
--        Requirement: GROUP BY one dimension, ORDER BY count DESC.
-- Finding: volume ranges from 21 reactions (Post_06) down to 6 (Post_04).
--          Post_14 and Post_15 do not appear at all: they have no
--          reactions, and GROUP BY can only group rows that exist.
--          Average dwell ranges from 11,941 ms (Post_11) to 23,057 ms
--          (Post_05).
SELECT
  post_id,
  COUNT(*)                 AS reactions,
  ROUND(AVG(dwell_ms))     AS avg_dwell_ms,
  COUNT(DISTINCT user_id)  AS distinct_actors
FROM likes
GROUP BY post_id
ORDER BY reactions DESC, post_id ASC;

-- 4.1-3  Which producers have enough volume for a rate to mean anything?
--        Keep only posts with at least 10 reactions.
--        Requirement: HAVING on an aggregate, with a stated threshold.
-- Threshold reasoning: 10 reactions is 5% of the table and half the
--   median per-post volume (16). Below it, a single spam removal moves
--   a post's rate by 10 points or more, which is noise, not signal.
-- Finding: 12 of 13 posts qualify. Post_04 (6 reactions) is excluded;
--          its one spam removal would otherwise show as a 16.7% rate.
SELECT
  post_id,
  COUNT(*)                 AS reactions,
  ROUND(AVG(dwell_ms))     AS avg_dwell_ms,
  COUNT(DISTINCT user_id)  AS distinct_actors
FROM likes
GROUP BY post_id
HAVING COUNT(*) >= 10
ORDER BY reactions DESC, post_id ASC;

-- 4.1-4  Two dimensions at once: for each region (client_country) and
--        each post, how many reactions and what average dwell?
--        One row per (region, post) combination.
--        Requirement: multi-column GROUP BY including region.
-- Finding: 62 (region, post) combinations out of a possible 65. 56 of
--          the 62 cells hold 5 or fewer reactions, so per-cell averages
--          swing widely; regional leaders should read these alongside
--          the per-post totals in 4.1-2 rather than on their own.
SELECT
  client_country           AS region,
  post_id,
  COUNT(*)                 AS reactions,
  ROUND(AVG(dwell_ms))     AS avg_dwell_ms,
  MIN(dwell_ms)            AS min_dwell_ms,
  MAX(dwell_ms)            AS max_dwell_ms
FROM likes
GROUP BY client_country, post_id
ORDER BY client_country, reactions DESC, post_id;
