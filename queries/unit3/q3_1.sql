-- ============================================================
-- EX603 Assignment 3, Task 3.1: Establish what the data contains
-- Theme: Social Media   Database: ex603_data (provided social.sql)
-- Roles: actor = users, producer = posts, event = likes (reactions)
-- ============================================================

-- 3.1a  Visible, well-liked posts: the producers whose records anchor
--       the audit. Which posts are visible and have more than 100 likes?
--       Requirement: SELECT, WHERE, ORDER BY, LIMIT (theme filter condition).
-- Finding: only 9 posts qualify, so LIMIT 10 returns 9. Four tie at 400 likes.
SELECT
  post_id,
  post_title,
  like_count
FROM posts
WHERE is_visible = TRUE
  AND like_count > 100
ORDER BY like_count DESC, post_id ASC
LIMIT 10;

-- 3.1b  Every status a reaction can have. Is "removed" the only
--       alternative to "active"?
--       Requirement: DISTINCT on the event status column.
-- Finding: three statuses, not two: active, flagged, removed. "Flagged" is
--          neither a success nor a failure, so a two-way split miscounts it.
SELECT DISTINCT reaction_status
FROM likes
ORDER BY reaction_status;

-- 3.1b (follow-up)  Every reason a reaction was removed. Is every
--       removal a spam removal?
--       Requirement: DISTINCT, IS NOT NULL.
-- Finding: four removal reasons. Spam is only one of them, so "removed"
--          does not mean "spam removal".
SELECT DISTINCT removal_reason
FROM likes
WHERE removal_reason IS NOT NULL
ORDER BY removal_reason;

-- 3.1c-1  Reactions where the user stayed on the post between 10 and
--         20 seconds (10,000 to 20,000 ms, both ends included).
--         Requirement: filter on a numeric range.
-- Finding: 48 of 200 reactions fall in this range. BETWEEN includes both ends.
SELECT
  like_id,
  user_id,
  post_id,
  dwell_ms
FROM likes
WHERE dwell_ms BETWEEN 10000 AND 20000
ORDER BY dwell_ms DESC, like_id ASC;

-- 3.1c-2  Reactions that are not in good standing: removed or flagged.
--         Requirement: filter with an explicit list using IN.
-- Finding: 44 reactions: 34 removed and 10 flagged. The other 156 are active.
SELECT
  like_id,
  user_id,
  post_id,
  reaction_status
FROM likes
WHERE reaction_status IN ('removed', 'flagged')
ORDER BY reaction_status, like_id;

-- 3.1d-1  Posts whose title matches the pattern "Post_0" plus one more
--         character: the first nine posts. In LIKE the underscore is
--         itself a wildcard for exactly one character, so the pattern
--         'Post_0_' reads: Post, any character, 0, any character.
--         Requirement: text pattern match with LIKE.
-- Finding: 9 posts match (Post_01 to Post_09). Post_10 to Post_15 do not.
SELECT
  post_id,
  post_title
FROM posts
WHERE post_title LIKE 'Post_0_'
ORDER BY post_id;

-- 3.1d-2  Reactions with no removal reason recorded. These are the rows
--         a careless filter on removal_reason will lose.
--         Requirement: identify missing values with IS NULL.
-- Finding: 166 reactions have no removal reason (the 156 active and 10
--          flagged ones). The query lists the first 10 of them.
SELECT
  like_id,
  reaction_status,
  removal_reason
FROM likes
WHERE removal_reason IS NULL
ORDER BY like_id
LIMIT 10;

-- 3.1d-3  The same column shown with a readable label in place of NULL.
--         Requirement: COALESCE to replace a missing value.
-- Finding: NULL now reads "No reason provided". The stored data is unchanged.
SELECT
  like_id,
  reaction_status,
  COALESCE(removal_reason, 'No reason provided') AS removal_reason_label
FROM likes
ORDER BY like_id
LIMIT 15;

-- 3.1e  A reaction list a non-SQL reader can follow: dwell time in
--       seconds, the part of the day, and a plain-language outcome.
--       Requirement: computed columns, aliases, CASE.
-- Finding: most reactions read "Counted". Removed reactions show 0 seconds
--          of dwell time, and only some of them are "Removed as spam".
SELECT
  like_id,
  post_id,
  dwell_ms / 1000.0 AS dwell_seconds,
  CASE
    WHEN EXTRACT(HOUR FROM liked_at) < 6  THEN 'overnight'
    WHEN EXTRACT(HOUR FROM liked_at) < 12 THEN 'morning'
    WHEN EXTRACT(HOUR FROM liked_at) < 18 THEN 'afternoon'
    ELSE 'evening'
  END AS time_of_day,
  CASE
    WHEN reaction_status = 'active'  THEN 'Counted'
    WHEN reaction_status = 'flagged' THEN 'Under review'
    WHEN removal_reason = 'Spam detected' THEN 'Removed as spam'
    ELSE 'Removed for another reason'
  END AS outcome
FROM likes
ORDER BY like_id
LIMIT 20;
