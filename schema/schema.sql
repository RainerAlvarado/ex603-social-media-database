-- =================================================================
-- EX 603 Assignment 2 — schema.sql
-- Theme:  Social Media — MLB Fan Social Platform
-- Author: Rainer Alvarado
-- Target: PostgreSQL 14+
-- =================================================================
-- Creation order (a table is created only after every table it references):
--   1. users          references nothing
--   2. posts          references users
--   3. likes          references users, posts
--   4. hashtags       references nothing (placed here to sit next to its junction)
--   5. post_hashtags  references posts, hashtags
-- The hashtag lifecycle functions and triggers are created last, because
-- they refer to both hashtags and post_hashtags.
-- =================================================================

-- -----------------------------------------------------------------
-- Reset. Reverse creation order, so no dependency blocks a drop.
-- Triggers are dropped with their tables; functions are not, so they
-- are dropped explicitly after the tables.
-- -----------------------------------------------------------------
DROP TABLE IF EXISTS post_hashtags CASCADE;
DROP TABLE IF EXISTS hashtags      CASCADE;
DROP TABLE IF EXISTS likes         CASCADE;
DROP TABLE IF EXISTS posts         CASCADE;
DROP TABLE IF EXISTS users         CASCADE;

DROP FUNCTION IF EXISTS fn_hashtag_cleanup_unused() CASCADE;
DROP FUNCTION IF EXISTS fn_hashtag_require_post()   CASCADE;


-- -----------------------------------------------------------------
-- 1. users — first, because it references no other table.
--    Every post and like points back here.
-- -----------------------------------------------------------------
CREATE TABLE users (
    user_id      INTEGER GENERATED ALWAYS AS IDENTITY,
    display_name VARCHAR(50) NOT NULL,
    CONSTRAINT pk_users PRIMARY KEY (user_id),
    -- At least one visible character; NOT NULL alone accepts '' and '   '.
    CONSTRAINT chk_users_display_name_not_blank
        CHECK (display_name ~ '[^[:space:]]')
);

-- Display names are unique regardless of capitalization
-- (BaseballFan = baseballfan). A plain UNIQUE constraint is case-sensitive,
-- so uniqueness is enforced on the lowercased value.
CREATE UNIQUE INDEX uq_users_display_name_ci
    ON users (LOWER(display_name));


-- -----------------------------------------------------------------
-- 2. posts — second, because every post references its author in users.
-- -----------------------------------------------------------------
CREATE TABLE posts (
    post_id         INTEGER GENERATED ALWAYS AS IDENTITY,
    author_id       INTEGER      NOT NULL,
    title           VARCHAR(100) NOT NULL,
    body            VARCHAR(280) NOT NULL,   -- 280-character short-post limit
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    -- Derived attribute: computed by the database from body, so it can
    -- never disagree with the text it describes.
    character_count INTEGER GENERATED ALWAYS AS (char_length(body)) STORED,
    CONSTRAINT pk_posts PRIMARY KEY (post_id),
    CONSTRAINT fk_posts_author
        FOREIGN KEY (author_id) REFERENCES users (user_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_posts_title_not_blank
        CHECK (title ~ '[^[:space:]]'),
    CONSTRAINT chk_posts_body_not_blank
        CHECK (body ~ '[^[:space:]]')
);


-- -----------------------------------------------------------------
-- 3. likes — third, because it references both users and posts.
--    Each row is one user liking one post, with the time of the like
--    and the viewing time before it.
-- -----------------------------------------------------------------
CREATE TABLE likes (
    like_id   INTEGER GENERATED ALWAYS AS IDENTITY,
    user_id   INTEGER     NOT NULL,
    post_id   INTEGER     NOT NULL,
    liked_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    dwell_ms  INTEGER     NOT NULL,          -- milliseconds viewed before liking
    CONSTRAINT pk_likes PRIMARY KEY (like_id),
    -- One like per user per post; a new like_id cannot bypass this.
    CONSTRAINT uq_likes_user_post UNIQUE (user_id, post_id),
    CONSTRAINT fk_likes_user
        FOREIGN KEY (user_id) REFERENCES users (user_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_likes_post
        FOREIGN KEY (post_id) REFERENCES posts (post_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_likes_dwell_nonnegative
        CHECK (dwell_ms >= 0)
);


-- -----------------------------------------------------------------
-- 4. hashtags — references no other table; created before post_hashtags,
--    which points at it.
-- -----------------------------------------------------------------
CREATE TABLE hashtags (
    hashtag_id INTEGER GENERATED ALWAYS AS IDENTITY,
    name       VARCHAR(51) NOT NULL,         -- '#' + up to 50 characters
    CONSTRAINT pk_hashtags PRIMARY KEY (hashtag_id),
    -- One leading '#', then 1–50 letters, digits, or underscores.
    CONSTRAINT chk_hashtags_name_format
        CHECK (name ~ '^#[A-Za-z0-9_]{1,50}$')
);

-- #OpeningDay and #openingday are the same hashtag.
CREATE UNIQUE INDEX uq_hashtags_name_ci
    ON hashtags (LOWER(name));


-- -----------------------------------------------------------------
-- 5. post_hashtags — last table, because it references posts and hashtags.
--    Resolves the M:N between posts and hashtags. The primary key is the
--    pair of foreign keys, not a new id.
-- -----------------------------------------------------------------
CREATE TABLE post_hashtags (
    post_id    INTEGER NOT NULL,
    hashtag_id INTEGER NOT NULL,
    CONSTRAINT pk_post_hashtags PRIMARY KEY (post_id, hashtag_id),
    CONSTRAINT fk_post_hashtags_post
        FOREIGN KEY (post_id) REFERENCES posts (post_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_post_hashtags_hashtag
        FOREIGN KEY (hashtag_id) REFERENCES hashtags (hashtag_id)
        ON DELETE CASCADE
);


-- =================================================================
-- Hashtag lifecycle: every retained hashtag must be used by at least
-- one post. Keys and CHECK constraints cannot express this, so it is
-- enforced with two deferred constraint triggers. Both run at COMMIT,
-- so a hashtag and its first post association can be inserted in the
-- same transaction, in either order.
-- =================================================================

-- 6a. Cleanup: when an association is removed (directly, or through a
--     cascade from a deleted post or user) or moved to another hashtag,
--     delete the former hashtag if nothing uses it at commit time.
CREATE FUNCTION fn_hashtag_cleanup_unused()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM hashtags h
    WHERE h.hashtag_id = OLD.hashtag_id
      AND NOT EXISTS (
          SELECT 1 FROM post_hashtags ph
          WHERE ph.hashtag_id = OLD.hashtag_id
      );
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_post_hashtags_cleanup
    AFTER DELETE OR UPDATE OF hashtag_id ON post_hashtags
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION fn_hashtag_cleanup_unused();

-- 6b. Validation: a new hashtag must have at least one post association
--     by the time its transaction commits, or the transaction is rejected.
CREATE FUNCTION fn_hashtag_require_post()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM hashtags WHERE hashtag_id = NEW.hashtag_id)
       AND NOT EXISTS (SELECT 1 FROM post_hashtags
                       WHERE hashtag_id = NEW.hashtag_id) THEN
        RAISE EXCEPTION 'Hashtag % must be attached to at least one post', NEW.name
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_hashtags_require_post
    AFTER INSERT ON hashtags
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION fn_hashtag_require_post();
