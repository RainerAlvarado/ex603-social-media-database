-- ============================================================
-- EX603 Assignment 3, Task 3.3: Hand the team a corrected query
-- Theme: Social Media   Database: ex603_data (provided social.sql)
-- Two-step question: (1) which reactions are flagged (the disputed
-- events), then (2) which users made them?
-- ============================================================

-- 3.3a  FORM 1: subquery with IN.
--       Which users made at least one flagged reaction?
SELECT
  user_id,
  user_name
FROM users
WHERE user_id IN (
  SELECT user_id
  FROM likes
  WHERE reaction_status = 'flagged'
)
ORDER BY user_id;

-- 3.3b  FORM 2: Common Table Expression.
--       Same question, with the flagged set named first.
WITH flagged_users AS (
  SELECT DISTINCT user_id
  FROM likes
  WHERE reaction_status = 'flagged'
)
SELECT
  user_id,
  user_name
FROM users
WHERE user_id IN (SELECT user_id FROM flagged_users)
ORDER BY user_id;

-- 3.3c  FORM 3: correlated EXISTS subquery.
--       Same question, asked per user: does a flagged reaction exist
--       for this user?
SELECT
  u.user_id,
  u.user_name
FROM users u
WHERE EXISTS (
  SELECT 1
  FROM likes l
  WHERE l.user_id = u.user_id
    AND l.reaction_status = 'flagged'
)
ORDER BY u.user_id;

-- 3.3d  PROOF that the three result sets are identical, row for row.
--       Each check lists rows that are in one form but not the other.
--       Every check must report 0. Both directions are tested, because
--       "A minus B is empty" alone would also be true if B had extra rows.
WITH form_in AS (
  SELECT user_id, user_name
  FROM users
  WHERE user_id IN (
    SELECT user_id FROM likes WHERE reaction_status = 'flagged'
  )
),
flagged_users AS (
  SELECT DISTINCT user_id
  FROM likes
  WHERE reaction_status = 'flagged'
),
form_cte AS (
  SELECT user_id, user_name
  FROM users
  WHERE user_id IN (SELECT user_id FROM flagged_users)
),
form_exists AS (
  SELECT u.user_id, u.user_name
  FROM users u
  WHERE EXISTS (
    SELECT 1
    FROM likes l
    WHERE l.user_id = u.user_id
      AND l.reaction_status = 'flagged'
  )
)
SELECT
  (SELECT COUNT(*) FROM form_in)     AS rows_in,
  (SELECT COUNT(*) FROM form_cte)    AS rows_cte,
  (SELECT COUNT(*) FROM form_exists) AS rows_exists,
  (SELECT COUNT(*) FROM (SELECT * FROM form_in     EXCEPT SELECT * FROM form_cte)    d) AS in_not_cte,
  (SELECT COUNT(*) FROM (SELECT * FROM form_cte    EXCEPT SELECT * FROM form_in)     d) AS cte_not_in,
  (SELECT COUNT(*) FROM (SELECT * FROM form_in     EXCEPT SELECT * FROM form_exists) d) AS in_not_exists,
  (SELECT COUNT(*) FROM (SELECT * FROM form_exists EXCEPT SELECT * FROM form_in)     d) AS exists_not_in;

-- 3.3e  WHERE EQUIVALENCE BREAKS: NULLs, once the question is negated.
--       The three forms above agree on any data, because IN and EXISTS
--       both simply fail to match a NULL. The negated forms do not agree.
--       Question: which users have never invited anyone?
--       users.invited_by is nullable (founding users have no inviter).
--
--       NOT IN version: returns 0 rows. The subquery contains NULLs, so
--       every comparison ends in UNKNOWN and WHERE discards every user.
SELECT COUNT(*) AS never_invited_not_in
FROM users
WHERE user_id NOT IN (
  SELECT invited_by
  FROM users
);

--       NOT EXISTS version: returns the real answer.
SELECT COUNT(*) AS never_invited_not_exists
FROM users u
WHERE NOT EXISTS (
  SELECT 1
  FROM users i
  WHERE i.invited_by = u.user_id
);

--       NOT IN made safe by filtering NULLs out of the subquery:
--       matches NOT EXISTS again.
SELECT COUNT(*) AS never_invited_not_in_safe
FROM users
WHERE user_id NOT IN (
  SELECT invited_by
  FROM users
  WHERE invited_by IS NOT NULL
);
