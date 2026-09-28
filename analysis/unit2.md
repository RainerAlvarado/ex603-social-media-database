# Task 2.2: Write up your reasoning

This document explains the decisions encoded in [`schema/schema.sql`](../schema/schema.sql). The script targets PostgreSQL 14+ and runs from top to bottom on an empty database. Because it begins with a reset block, it can also be run a second time without manual cleanup.

## Creation order

| Order | Table | References | Why it sits here |
|---|---|---|---|
| 1 | `users` | nothing | Every post and like points back to a user. |
| 2 | `posts` | `users` | Each post needs an existing author. |
| 3 | `likes` | `users`, `posts` | A like connects an existing user to an existing post. |
| 4 | `hashtags` | nothing | Has no outgoing references; created just before the junction that uses it. |
| 5 | `post_hashtags` | `posts`, `hashtags` | Both sides of the association must already exist. |

The hashtag lifecycle functions and triggers are created after all five tables because they read from both `hashtags` and `post_hashtags`. The reset block drops the tables in reverse order, then drops the two trigger functions, which PostgreSQL does not remove along with the tables.

## Type decisions

- **Identifiers** use `INTEGER GENERATED ALWAYS AS IDENTITY`. PostgreSQL assigns them, so they start at 1 and stay positive without a separate CHECK, and an application cannot insert its own IDs by accident.
- **Text lengths** come from the domains in Unit 1, not from a default of 255: `display_name VARCHAR(50)`, `title VARCHAR(100)`, `body VARCHAR(280)` for the short-post limit, and `name VARCHAR(51)` for a `#` plus up to 50 characters.
- **`liked_at` uses `TIMESTAMPTZ`** instead of plain `TIMESTAMP`. My Unit 1 domain called for time-zone support. Fans react to games played across every U.S. time zone, and storing an absolute point in time keeps "likes during the 7th inning" comparable no matter where the user was.
- **`dwell_ms` is an `INTEGER`** with the unit in its name, as the course recommends for durations.
- **`is_active` is a `BOOLEAN`** with a default of `TRUE`, because a newly created post is visible.

## Derived value: `character_count`

I kept `character_count` as a stored generated column: `GENERATED ALWAYS AS (char_length(body)) STORED`. The course default is to compute derived values at query time, and I considered dropping the column. I kept it because Unit 1 committed to supporting length-based filtering, and a generated column removes the risk that normally argues against storing a derived value. PostgreSQL recalculates it on every insert and update, and no application can write to it directly, so it can never disagree with the body. I tested this by editing a post's body and confirming the count changed with it. The body's length limit is enforced by `VARCHAR(280)` and the not-blank check, so the count's 1–280 range follows automatically.

## Foreign keys and ON DELETE behavior

| Foreign key | ON DELETE | Reason |
|---|---|---|
| `posts.author_id` → `users.user_id` | CASCADE | The platform does not keep posts after their author's account is removed. |
| `likes.user_id` → `users.user_id` | CASCADE | A like cannot remain attributed to an account that no longer exists. |
| `likes.post_id` → `posts.post_id` | CASCADE | A like on a post that no longer exists has nothing to describe. |
| `post_hashtags.post_id` → `posts.post_id` | CASCADE | A deleted post's hashtag tags should disappear with it. |
| `post_hashtags.hashtag_id` → `hashtags.hashtag_id` | CASCADE | Removing a hashtag should untag its posts, not block the removal or delete the posts. |

**A user deletes their account.** This single event triggers most of the cascades. The user's posts are deleted through `fk_posts_author`. Their likes on other people's posts are deleted through `fk_likes_user`. The likes other users gave to the deleted posts are deleted through `fk_likes_post`, and those posts' hashtag tags go through `fk_post_hashtags_post`. The people affected are other fans: their likes on the removed posts disappear from their "liked posts" history, and like counts on the platform drop. I accept that because the platform promises to remove a departing user's content. Under RESTRICT, account deletion would be blocked until every post and like was removed by hand, and a user asking to leave would be stuck. SET NULL is not an option: `author_id` is required, and a post with no author would break the rule that every post belongs to someone.

**A user deletes one post, or a moderator removes it.** The likes on that post and its hashtag tags are removed. The users who liked it are not affected beyond losing that like, and hashtags still used by other posts remain. Under RESTRICT, a post could not be deleted as long as anyone had liked it. A user could lose control over their own content just because it was popular.

**A user is removed but their likes were on posts that remain.** `fk_likes_user` removes only that user's like rows. The posts they liked stay, with one fewer like. The alternative of keeping the likes with a NULL user would leave anonymous likes that inflate counts and could never be traced or removed again.

**A moderator removes a hashtag directly**, for example an offensive tag. `fk_post_hashtags_hashtag` removes the tag from every post that used it, while the posts themselves stay. Under RESTRICT, a moderator would have to untag every post before deleting the hashtag, which is exactly the situation where fast removal matters. CASCADE on this side deletes only association rows, never posts.

## CHECK constraints

**`chk_users_display_name_not_blank`** requires at least one non-whitespace character. `NOT NULL` accepts an empty string or a name made only of spaces, so without this check a signup form or an import script could store a user whose public name renders as nothing. The 50-character maximum is enforced by `VARCHAR(50)`.

**`chk_posts_title_not_blank`** and **`chk_posts_body_not_blank`** apply the same rule to a post's title and body. A client that submits whitespace, or a bulk import with empty fields, would otherwise create posts that appear blank in a feed but still collect likes and hashtags. The 280-character body limit is enforced by `VARCHAR(280)`. I tested it with a 281-character body, which was rejected.

**`chk_likes_dwell_nonnegative`** requires `dwell_ms >= 0`. A negative viewing time is impossible. It could still arise from a client clock that moves backward between page load and the like, or from a bug that subtracts timestamps in the wrong order. Zero is allowed, because a user can like a post instantly. The database can only guarantee the value is plausible; the application is responsible for measuring it correctly.

**`chk_hashtags_name_format`** requires one leading `#` followed by 1–50 letters, digits, or underscores. Without it, `OpeningDay`, `#Opening Day`, and `##OpeningDay` could all be stored as separate topics, splitting one discussion across several records. Manual entry, pasted text, and a mobile keyboard that adds a trailing space are all realistic ways this could happen.

### Rules that are not CHECK constraints

Two Unit 1 rules could not be written as CHECKs, so I want to name how they are enforced.

- **Case-insensitive uniqueness.** A plain `UNIQUE` constraint treats `BaseballFan` and `baseballfan` as different values, just as a CHECK treats `'PREMIUM'` and `'premium'` as different. I used unique indexes on `LOWER(display_name)` and `LOWER(name)` (`uq_users_display_name_ci`, `uq_hashtags_name_ci`). The original capitalization is still stored for display.
- **Every hashtag must be used by at least one post.** A CHECK can only look at a single row, so this rule needs triggers. `trg_hashtags_require_post` rejects a transaction that commits a hashtag with no post attached. `trg_post_hashtags_cleanup` deletes a hashtag once its last post association is removed, including when the removal comes from a cascade. Both are deferred to commit time, so a hashtag and its first association can be inserted in the same transaction. I tested first use, a standalone hashtag (rejected), removal of the last use (cleaned up), removal while another post still uses the tag (kept), and direct hashtag deletion (posts kept).

## Changes from the Unit 1 design

- **`character_count` is now generated by the database** instead of being a stored value that had to be kept equal to the body length. The attribute, its meaning, and its place in the ERD are unchanged; only the enforcement mechanism is more reliable. The ERD therefore did not need structural changes.
- **Concurrency protection for hashtags moved to the application.** Unit 1 specified that the database should reject membership changes made below serializable isolation. While planning the implementation, I realized that this check would also reject routine operations such as deleting a user, whose cascades change hashtag membership, unless every client changed its default isolation level. I kept the cleanup and validation triggers in the database. Running those transactions at serializable isolation and retrying on conflict is now documented as an application responsibility.
- **`likes` keeps its surrogate `like_id`** with a `UNIQUE (user_id, post_id)` constraint, as designed in Unit 1, rather than switching to a composite primary key. I model a like as an event record with its own attributes (`liked_at`, `dwell_ms`), and a single-column key keeps future features such as notifications or moderation logs simple to reference. The unique pair still guarantees one like per user per post.
