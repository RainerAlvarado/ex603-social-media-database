# Task 1.1 Define the relation schema

This document defines the relations, attributes, domains, and primary keys for a short-post social platform for Major League Baseball fans.

## Relations

- [Users](#users)
- [Posts](#posts)
- [Likes](#likes)
- [Hashtags](#hashtags)
- [Post hashtags](#post_hashtags)

**Reading the definitions:** A domain specifies the allowed values. A constraint specifies a rule the data must satisfy. Every attribute listed below is required (not null).

Foreign-key deletion policies will be documented separately in the integrity-constraint documentation.

---

## users

Stores registered platform users. Each row represents one user.

**Relation schema:** `users(user_id, display_name)`  
**Primary key:** `user_id`

### Attributes

#### `user_id`

- **Description:** Stable identifier for a user
- **Domain:** Positive whole numbers
- **Constraints:** Primary key; unique; not null

#### `display_name`

- **Description:** Public name displayed for a user
- **Domain:** Text containing 1–50 characters and at least one non-space character
- **Constraints:** Not null; unique regardless of capitalization

### Relation rules and notes

Display-name uniqueness is case-insensitive: `BaseballFan`, `baseballfan`, and `BASEBALLFAN` represent the same name for uniqueness checks. A user's identifier remains unchanged when their display name changes.

---

## posts

Stores short baseball-related posts. Each row represents one post written by exactly one user.

**Relation schema:** `posts(post_id, author_id, title, body, is_active, character_count)`  
**Primary key:** `post_id`

### Attributes

#### `post_id`

- **Description:** Stable identifier for a post
- **Domain:** Positive whole numbers
- **Constraints:** Primary key; unique; not null

#### `author_id`

- **Description:** Identifier of the user who wrote the post
- **Domain:** Positive whole numbers
- **Constraints:** Not null; foreign key referencing `users.user_id`

#### `title`

- **Description:** Short display name for the post
- **Domain:** Text containing 1–100 characters and at least one non-space character
- **Constraints:** Not null; duplicate titles are permitted

#### `body`

- **Description:** Main content of the post
- **Domain:** Text containing 1–280 characters and at least one non-space character
- **Constraints:** Not null; duplicate body text is permitted

#### `is_active`

- **Description:** Whether the post is available for display on the platform
- **Domain:** Boolean: true or false
- **Constraints:** Not null

#### `character_count`

- **Description:** Length of the post body in characters
- **Domain:** Whole numbers from 1 through 280
- **Constraints:** Not null; must equal the actual character length of `body`

### Relation rules and notes

The title serves as the post's display name. The title and body have separate length limits; the 280-character limit applies only to the body. Posts are identified uniquely by `post_id`, not by their title or body text.

A user can write zero or many posts. Each post references exactly one author. The numeric `character_count` attribute supports filtering by post length and must remain consistent with the body. Deletion behavior for the author reference will be specified in the integrity-constraint documentation.

---

## likes

Stores user likes on posts. Each row represents one user liking one post.

**Relation schema:** `likes(like_id, user_id, post_id, liked_at, dwell_ms)`  
**Primary key:** `like_id`

### Attributes

#### `like_id`

- **Description:** Stable identifier for a like
- **Domain:** Positive whole numbers
- **Constraints:** Primary key; unique; not null

#### `user_id`

- **Description:** Identifier of the user who liked the post
- **Domain:** Positive whole numbers
- **Constraints:** Not null; foreign key referencing `users.user_id`

#### `post_id`

- **Description:** Identifier of the post that was liked
- **Domain:** Positive whole numbers
- **Constraints:** Not null; foreign key referencing `posts.post_id`

#### `liked_at`

- **Description:** Time when the user liked the post
- **Domain:** Date and time with time-zone support
- **Constraints:** Not null

#### `dwell_ms`

- **Description:** Time spent viewing the post during the visit before liking it, measured in milliseconds
- **Domain:** Nonnegative whole numbers
- **Constraints:** Not null

The pair `(user_id, post_id)` must be unique, preventing a user from having more than one like on the same post. This rule is separate from the uniqueness of `like_id`: assigning a new identifier does not allow a duplicate user–post pair.

Each like references exactly one user and one post. A user can have zero or many likes, and a post can receive zero or many likes from different users. Deletion behavior for both references will be specified in the integrity-constraint documentation.

A `dwell_ms` value of `4000` represents four seconds of viewing before the like. Time spent viewing after the like is excluded, and viewing visits that do not result in a like are not recorded in this relation.

---

## hashtags

Stores the hashtags used to categorize posts. Each row represents one hashtag.

**Relation schema:** `hashtags(hashtag_id, name)`  
**Primary key:** `hashtag_id`

### Attributes

#### `hashtag_id`

- **Description:** Stable identifier for a hashtag
- **Domain:** Positive whole numbers
- **Constraints:** Primary key; unique; not null

#### `name`

- **Description:** Hashtag text, including its leading `#`
- **Domain:** Text containing 2–51 characters: one leading `#` followed by 1–50 letters, numbers, or underscores
- **Constraints:** Not null; unique regardless of capitalization; no spaces or additional `#` characters

### Relation rules and notes

The `#` prefix is stored as part of the name, as in `#OpeningDay` or `#RedSox`. Name uniqueness is case-insensitive: `#OpeningDay` and `#openingday` represent the same hashtag and cannot be stored as separate records.

Each hashtag is stored once in this relation. Associations between hashtags and posts are stored separately in `post_hashtags`, allowing the same hashtag to categorize multiple posts.

A hashtag must be associated with at least one post. When its last post association is removed, the hashtag is removed as well. Enforcing this minimum participation and cleanup requires an additional integrity rule; foreign keys and cascading deletion of association rows alone do not enforce it.

---

## post_hashtags

Connects posts to their hashtags. Each row represents one hashtag attached to one post.

**Relation schema:** `post_hashtags(post_id, hashtag_id)`  
**Primary key:** `(post_id, hashtag_id)` — composite primary key

### Attributes

#### `post_id`

- **Description:** Identifier of the post using the hashtag
- **Domain:** Positive whole numbers
- **Constraints:** Not null; foreign key referencing `posts.post_id`; part of the composite primary key

#### `hashtag_id`

- **Description:** Identifier of the hashtag attached to the post
- **Domain:** Positive whole numbers
- **Constraints:** Not null; foreign key referencing `hashtags.hashtag_id`; part of the composite primary key

### Relation rules and notes

The pair `(post_id, hashtag_id)` must be unique. Each identifier can repeat individually, but the same hashtag cannot be attached to the same post more than once. No separate identifier is needed for the association.

Hashtags are optional: a post can have zero or many associated hashtags. A post with no hashtags has no rows in `post_hashtags`; it does not require a row with a missing hashtag identifier. A hashtag must be associated with one or many posts. Every association references exactly one existing post and one existing hashtag.

Deletion behavior for both references will be specified in the integrity-constraint documentation.
