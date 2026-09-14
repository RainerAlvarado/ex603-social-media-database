# Task 1.4: Write up your reasoning

## Modeling Justification

I designed this database for a social platform where Major League Baseball fans share short posts, like other users’ content, and organize discussions with hashtags. The five relations separate the people using the platform, the posts they create, their likes, the available hashtags, and the connections between posts and hashtags. Keeping these responsibilities separate makes it possible to connect the data without storing a list of hashtags inside each post.

I chose positive numeric primary keys for users, posts, likes, and hashtags. These identifiers remain stable when descriptive information changes. For example, a user can change their display name without changing the identifier referenced by their posts and likes. Display names are also required to be unique regardless of capitalization. This prevents someone from registering “baseballfan” when “BaseballFan” is already taken. Hashtag names follow the same uniqueness rule so capitalization does not separate posts about the same topic.

The post_hashtags relation uses a composite primary key consisting of post_id and hashtag_id. Either identifier can appear in multiple rows, but their combination cannot repeat. This allows a post to have several hashtags while preventing the same hashtag from being attached twice. Likes have their own primary key and an additional unique constraint on the user_id and post_id pair. A new like identifier therefore cannot bypass the rule that a user may like a particular post only once.

Every post requires one author, but users do not have to create posts. Hashtags are optional for posts. Each post has a title that serves as its display name and a body limited to 280 characters. The activity flag distinguishes active from inactive posts, while character_count supports filtering by body length. I require that count to match the actual body so an edit cannot leave misleading length information. For likes, I interpret dwell_ms as viewing time during the visit before liking, measured in whole milliseconds. Negative values are invalid, while zero is allowed.

I selected ON DELETE CASCADE for all five foreign keys because the dependent records should disappear when the records they describe are removed. Deleting a user removes their authored posts and the likes they gave. Deleting a post removes its likes and hashtag connections, including when the post is removed through its author. Deleting a hashtag removes its connections but preserves the posts. These choices keep references valid, although they also mean deleted content and interactions are unavailable for historical analysis.

I chose to enforce required values, valid domains, uniqueness, foreign keys, and body-length consistency in the database rather than relying only on application checks. The unused-hashtag rule needs additional enforcement: cascading deletion removes connections, but does not remove the hashtag they previously referenced. The design therefore specifies database triggers, validation before a transaction commits, and coordination of simultaneous changes. The application remains responsible for measuring viewing time and presenting useful errors. These are design commitments; their implementation and behavior still need to be tested when the database is built.

---

## Reflection

One decision the requirements left open was whether a hashtag should remain after its last post connection disappears. I chose to remove it. A different designer could reasonably keep unused hashtags for reuse or historical reporting, especially on a platform where topics return every season.

For this project, I want the hashtag catalog to describe discussions that currently have posts attached to them. That choice supports browsing and searching: listing the catalog will not offer a topic with no associated posts. A retained hashtag could still have only inactive posts, so queries for visible content would also need to consider the posts’ activity flags.

The tradeoff is additional work during writes. Removing a post can require checking its hashtags and deleting any that are no longer used. Simultaneous changes make that check more complicated, and a returning topic may require a new hashtag record. Keeping unused hashtags would avoid some of that work.

I still prefer removal for the current scope because it gives the catalog a clear meaning. If the platform later needed long-term topic analysis, I would reconsider this choice. Retaining hashtag identities could then be more useful than keeping the catalog limited to current associations.
