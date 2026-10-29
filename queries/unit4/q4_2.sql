-- ============================================================
-- EX603 Assignment 4, Task 4.2: Build the breakdown leadership asked for
-- Theme: Social Media   Database: ex603_data (provided social.sql)
-- Roles: actor = users, producer = posts, event = likes (reactions)
-- Failure: reaction_status = 'removed' AND removal_reason = 'Spam detected'
-- Region: likes.client_country
-- ============================================================

-- 4.2-A  Two numbers in one pass. For each post: total reactions and
--        reactions that failed (removed as spam), from a single scan
--        of likes with no WHERE clause. The failure rate is derived
--        from the two columns in the same row.
--        Requirement: CASE inside an aggregate; both totals as
--        separate columns in one result set.
-- Finding: 12 spam removals across 200 reactions (6.0%). Post_02 has
--          3 of the 12 (18.8% of its reactions) and Post_03 has 2
--          (15.4%). Five posts have zero. The CASE approach also lets a
--          third column, non-spam removals, ride along in the same pass.
SELECT
  post_id,
  COUNT(*) AS total_reactions,
  SUM(CASE WHEN reaction_status = 'removed'
            AND removal_reason = 'Spam detected' THEN 1 ELSE 0 END)
    AS spam_removals,
  COUNT(CASE WHEN reaction_status = 'removed'
              AND removal_reason <> 'Spam detected' THEN 1 END)
    AS other_removals,
  ROUND(
    100.0 * SUM(CASE WHEN reaction_status = 'removed'
                      AND removal_reason = 'Spam detected' THEN 1 ELSE 0 END)
    / COUNT(*), 1)
    AS spam_rate_pct
FROM likes
GROUP BY post_id
ORDER BY spam_rate_pct DESC, total_reactions DESC, post_id;

-- 4.2-B  Subtotals per region and a platform grand total, without the
--        (region, post) detail rows. GROUPING SETS names exactly the
--        two levels wanted: one row per region, and one row for all.
--        Requirement: ROLLUP / GROUPING SETS / CUBE; identify which
--        rows are subtotals and which is the grand total.
-- How to read the output: GROUPING(client_country) = 0 marks a
--   regional subtotal (region named). GROUPING(client_country) = 1
--   marks the grand total; its region column is a synthetic NULL,
--   labelled 'ALL REGIONS' so it cannot be mistaken for real data.
-- Finding: five regional subtotals of 38-43 reactions each, and a
--          grand total of 200 with 12 spam removals. India has 4 of
--          the 12, UK and Vietnam 1 each. Regional subtotals sum to
--          the grand total exactly, which confirms nothing was dropped.
SELECT
  CASE WHEN GROUPING(client_country) = 1 THEN 'ALL REGIONS'
       ELSE client_country END              AS region,
  GROUPING(client_country)                  AS is_grand_total,
  COUNT(*)                                  AS total_reactions,
  SUM(CASE WHEN reaction_status = 'removed'
            AND removal_reason = 'Spam detected' THEN 1 ELSE 0 END)
                                            AS spam_removals,
  ROUND(AVG(dwell_ms))                      AS avg_dwell_ms,
  COUNT(DISTINCT user_id)                   AS distinct_actors
FROM likes
GROUP BY GROUPING SETS ((client_country), ())
ORDER BY is_grand_total, region;

-- 4.2-B (alternative)  The same two levels with ROLLUP. ROLLUP over
--        one column produces exactly (client_country) and (), so it is
--        equivalent to the GROUPING SETS form above. Kept for reference.
SELECT
  COALESCE(client_country, 'ALL REGIONS')   AS region,
  GROUPING(client_country)                  AS is_grand_total,
  COUNT(*)                                  AS total_reactions,
  SUM(CASE WHEN reaction_status = 'removed'
            AND removal_reason = 'Spam detected' THEN 1 ELSE 0 END)
                                            AS spam_removals
FROM likes
GROUP BY ROLLUP (client_country)
ORDER BY is_grand_total, region;

-- 4.2-C  A two-step pipeline. Step 1 summarises each post: reactions,
--        spam removals, spam rate. Step 2 keeps only high-volume posts
--        (at least the platform-average number of reactions per post,
--        computed rather than hard-coded) and derives a baseline from
--        them. Step 3 compares every high-volume post to that baseline.
--        Requirement: WITH clause producing an intermediate aggregate;
--        a second aggregation or filter applied to it.
-- Question answered: what spam-removal rate should a high-volume post
--   be measured against, and which high-volume posts sit above it?
-- Finding: the average post has 15.4 reactions, so "high volume" is
--          16 or more: 8 posts. Their pooled baseline is 7 spam
--          removals in 145 reactions (4.8%). Post_02 is 3.9x that
--          baseline at 18.8%; every other high-volume post is at or
--          below 6.3%.
WITH producer_stats AS (
  SELECT
    post_id,
    COUNT(*) AS total_reactions,
    SUM(CASE WHEN reaction_status = 'removed'
              AND removal_reason = 'Spam detected' THEN 1 ELSE 0 END)
      AS spam_removals
  FROM likes
  GROUP BY post_id
),
volume_cutoff AS (
  SELECT CEIL(AVG(total_reactions)) AS min_reactions
  FROM producer_stats
),
high_volume AS (
  SELECT p.*
  FROM producer_stats p
  CROSS JOIN volume_cutoff v
  WHERE p.total_reactions >= v.min_reactions
),
baseline AS (
  SELECT
    COUNT(*)                                        AS high_volume_posts,
    SUM(total_reactions)                            AS pooled_reactions,
    SUM(spam_removals)                              AS pooled_spam,
    ROUND(100.0 * SUM(spam_removals) / SUM(total_reactions), 1)
                                                    AS baseline_spam_pct
  FROM high_volume
)
SELECT
  h.post_id,
  h.total_reactions,
  h.spam_removals,
  ROUND(100.0 * h.spam_removals / h.total_reactions, 1)   AS spam_rate_pct,
  b.baseline_spam_pct,
  ROUND((100.0 * h.spam_removals / h.total_reactions) / b.baseline_spam_pct, 1)
                                                          AS times_baseline,
  b.high_volume_posts,
  b.pooled_reactions
FROM high_volume h
CROSS JOIN baseline b
ORDER BY spam_rate_pct DESC, h.total_reactions DESC, h.post_id;
