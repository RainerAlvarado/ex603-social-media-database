# Task 1.3: Specify integrity constraints

This document defines the rules that protect the integrity of the MLB-focused social platform’s data. Attribute domains and relation schemas are documented in [Schema Definition](schema-definition.md).

## Relations

- [Users](#users)
- [Posts](#posts)
- [Likes](#likes)
- [Hashtags](#hashtags)
- [Post hashtags](#post_hashtags)

**Reading the definitions:** Each constraint states its rule and justification. All attributes are required. All five foreign-key deletion policies use CASCADE. The hashtag lifecycle additionally requires database triggers and coordinated transactions, as specified below. This document specifies the design; it does not claim that the constraints have been implemented or tested in PostgreSQL.

---

## users

### Attribute constraints

#### `user_id`

- **Domain:** Positive whole numbers.
- **Constraint:** Primary key; unique; not null.
- **Justification:** Ensures that every user has a distinct identifier that remains stable when their display name changes.

#### `display_name`

- **Domain:** Text containing 1–50 characters and at least one non-space character.
- **Constraint:** Not null; unique regardless of capitalization.
- **Justification:** Ensures that every user has a usable public name and prevents another account from taking the same name by changing its capitalization.

### Relation rules and notes

Display-name uniqueness must use case-insensitive comparison: `BaseballFan` and `baseballfan` cannot belong to different users. A plain text uniqueness constraint must not be assumed to provide this comparison automatically.

This design does not require users to author a post or give a like.

---

## posts

### Attribute constraints

#### `post_id`

- **Domain:** Positive whole numbers.
- **Constraint:** Primary key; unique; not null.
- **Justification:** Distinguishes posts even when their titles or body text are identical.

#### `author_id`

- **Domain:** Positive whole numbers.
- **Constraint:** Not null; foreign key referencing `users.user_id`.
- **Justification:** Prevents posts with missing or nonexistent authors and ensures that every post belongs to exactly one user.
- **ON DELETE:** CASCADE.
- **Deletion justification:** Deleting a user also deletes all posts they authored. The platform does not retain posts after their author’s account is removed, preserving the rule that every stored post has an existing author.

#### `title`

- **Domain:** Text containing 1–100 characters and at least one non-space character.
- **Constraint:** Not null; duplicate titles are permitted.
- **Justification:** Provides a nonempty display name for each post while limiting its length. Titles do not identify posts uniquely.

#### `body`

- **Domain:** Text containing 1–280 characters and at least one non-space character.
- **Constraint:** Not null; duplicate body text is permitted.
- **Justification:** Prevents empty or oversized posts while preserving the platform’s short-post format.

#### `is_active`

- **Domain:** Boolean: true or false.
- **Constraint:** Not null.
- **Justification:** Ensures that each post has an explicit active or inactive status instead of an unknown status.

#### `character_count`

- **Domain:** Whole numbers from 1 through 280.
- **Constraint:** Not null; must equal the actual character length of `body`.
- **Justification:** Keeps post-length filtering consistent with the actual body. A stored count that differs from the body length would produce incorrect results.

### Relation rules and notes

The title and body have separate length limits. The body’s 280-character limit does not include the title. Duplicate titles and duplicate body text are permitted because `post_id` supplies identity.

The character-count equality must remain valid when a post is inserted or its body is edited. This is a rule involving two attributes of the same row and belongs in database enforcement.

Changing `is_active` is an update, not a deletion, so it does not invoke an `ON DELETE` policy.

---

## likes

### Attribute constraints

#### `like_id`

- **Domain:** Positive whole numbers.
- **Constraint:** Primary key; unique; not null.
- **Justification:** Gives each like a distinct identifier, independent of the user and post identifiers.

#### `user_id`

- **Domain:** Positive whole numbers.
- **Constraint:** Not null; foreign key referencing `users.user_id`.
- **Justification:** Prevents likes from referring to nonexistent or unspecified users.
- **ON DELETE:** CASCADE.
- **Deletion justification:** Deleting a user removes the likes they gave, so no like remains attributed to a removed account. This cascade deletes the user's like records; it does not delete other users' posts that received those likes.

#### `post_id`

- **Domain:** Positive whole numbers.
- **Constraint:** Not null; foreign key referencing `posts.post_id`.
- **Justification:** Prevents likes from referring to nonexistent or unspecified posts.
- **ON DELETE:** CASCADE.
- **Deletion justification:** Deleting a post removes all likes on it because those interactions have no remaining post to reference. This also applies when the post is deleted as a consequence of deleting its author. The users who gave those likes remain unaffected by this cascade.

#### `liked_at`

- **Domain:** Date and time with time-zone support.
- **Constraint:** Not null.
- **Justification:** Records when each like occurred using a time representation that can distinguish time zones.

#### `dwell_ms`

- **Domain:** Nonnegative whole numbers.
- **Constraint:** Not null.
- **Justification:** Prevents missing, fractional, or negative millisecond measurements. Zero is allowed; time after liking is excluded from this metric’s definition.

### Relation rules and notes

#### Unique user–post pair

- **Constraint:** The pair `(user_id, post_id)` must be unique.
- **Justification:** A user may have only one like on a particular post. A different `like_id` does not permit a duplicate user–post pair.

#### Viewing-time meaning

- **Definition:** `dwell_ms` measures viewing time during the visit before the user liked the post.
- **Enforcement boundary:** The database can require a nonnegative whole number, but it cannot independently verify that this number matches the user’s actual viewing time. Measurement belongs to the application.

---

## hashtags

### Attribute constraints

#### `hashtag_id`

- **Domain:** Positive whole numbers.
- **Constraint:** Primary key; unique; not null.
- **Justification:** Provides a distinct identifier for each hashtag, separate from its displayed text.

#### `name`

- **Domain:** Text containing 2–51 characters: one leading `#` followed by 1–50 letters, numbers, or underscores.
- **Constraint:** Not null; unique regardless of capitalization; no spaces or additional `#` characters.
- **Justification:** Keeps hashtag names in a consistent format and prevents capitalization variants from splitting the same topic into separate records.

### Relation rules and notes

#### Hashtag format and uniqueness

- **Constraint:** Store one leading `#` followed by 1–50 letters, numbers, or underscores. Names must be unique regardless of capitalization.
- **Justification:** `#OpeningDay` and `#openingday` must refer to the same topic. The required prefix and restricted format prevent inconsistent hashtag strings.

#### Required post association

- **Constraint:** Every retained hashtag must have at least one association in `post_hashtags` when a transaction commits. Remove the hashtag when its last association is removed. A transaction is a group of changes that are saved together or rolled back together.
- **Justification:** The catalog should contain only hashtags that are used by posts, matching the platform’s chosen lifecycle.
- **Enforcement boundary:** Foreign keys ensure that an association has a valid hashtag; they do not ensure that every hashtag has an association. Cascading deletion of association rows also does not automatically remove their parent hashtag.
- **Enforcement design:** Use database triggers for cleanup and deferred validation. A trigger runs automatically in response to a specified data change. Deferred validation checks the completed transaction, allowing related changes to be made together before the rule is evaluated.

#### Creating a hashtag

- **Rule:** Create a hashtag and its first post association in the same transaction.
- **Validation:** A deferred constraint trigger checks newly inserted hashtags and any changed hashtag identifiers. If a hashtag still exists but has no association when validation runs, reject the transaction. If it has already been deleted, there is no retained hashtag to validate.
- **Justification:** An immediate check would reject a new hashtag before its first association could be inserted. Checking the completed transaction permits creation while preventing an unused hashtag from being saved on its own.

#### Removing the last association

- **Trigger events:** Deletion of a `post_hashtags` row or a change to its `hashtag_id`, including deletions caused by foreign-key cascades.
- **Cleanup:** Before commit, check the affected former hashtag against the transaction's final associations. If it still exists and no associations reference it, delete it. Otherwise, retain it.
- **Justification:** This covers post deletion, account deletion that cascades to posts, removal of a hashtag from a post, and reassignment of an association to another hashtag. A temporary removal followed by a replacement association in the same transaction need not remove a still-used hashtag.
- **Direct hashtag deletion:** If the hashtag itself has already been deleted, cleanup does nothing. Its existing foreign-key cascade removes the associations without removing the posts.

#### Simultaneous changes

- **Rule:** Transactions that can change hashtag membership must use serializable isolation, with database-side checks rejecting these writes at weaker isolation. This includes cascaded changes initiated by deleting posts or users.
- **Conflict handling:** If PostgreSQL rejects a transaction because concurrent changes cannot be safely serialized, retry the entire transaction. A transaction must not be treated as saved until commit succeeds.
- **Justification:** Two simultaneous removals could otherwise each observe the other association and both leave an unused hashtag. Serializable execution protects against this inconsistent combined result; the retry completes the operation against the updated data.

#### Implementation scope

- **Database responsibility:** Enforce references, perform cleanup, validate retained hashtags, and require the transaction conditions described above. Bulk operations must not bypass these rules.
- **Application responsibility:** Group related writes into a transaction, retry serialization conflicts, and report validation errors to the user.
- **Verification required during implementation:** Test first use, invalid standalone creation, last-use removal, removal with other uses remaining, reassignment, cascading deletion, direct hashtag deletion, and concurrent changes. No SQL is included in this design document.

PostgreSQL supports change-triggered actions and deferred constraint validation; these provide the mechanisms for this project's lifecycle policy. See [CREATE TRIGGER](https://www.postgresql.org/docs/current/sql-createtrigger.html) and [Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html).

---

## post_hashtags

### Attribute constraints

#### `post_id`

- **Domain:** Positive whole numbers.
- **Constraint:** Not null; foreign key referencing `posts.post_id`; part of the composite primary key.
- **Justification:** Ensures that each association refers to an existing post.
- **ON DELETE:** CASCADE.
- **Deletion justification:** Deleting a post removes its hashtag associations, including when the post is deleted because its author is removed. Hashtags still used by other posts remain. Removing a hashtag that becomes unused is handled by the separate hashtag lifecycle rule, not by this foreign-key cascade alone.

#### `hashtag_id`

- **Domain:** Positive whole numbers.
- **Constraint:** Not null; foreign key referencing `hashtags.hashtag_id`; part of the composite primary key.
- **Justification:** Ensures that each association refers to an existing hashtag.
- **ON DELETE:** CASCADE.
- **Deletion justification:** Deleting a hashtag removes all associations that reference it, preventing connections to a nonexistent hashtag. The associated posts remain; they simply lose that hashtag association.

### Relation rules and notes

#### Composite primary key

- **Constraint:** `(post_id, hashtag_id)` is the composite primary key. The complete pair must be unique, and neither attribute may be null.
- **Justification:** Prevents a post from being associated with the same hashtag twice. Either identifier may repeat separately, allowing the many-to-many relationship.

#### Optional hashtags on posts

- **Constraint:** A post may have no rows in `post_hashtags`. An existing association must reference both a post and a hashtag.
- **Justification:** Hashtags are optional for posts; absence is represented by no association row, rather than a row containing a null identifier.

Removing an association must also respect the hashtag lifecycle rule described under [Hashtags](#hashtags).
