# Unit 4: From Rows to Insight

**Database:** `ex603_data` (course-provided `social.sql`)
**Roles:** actor = `users`, producer = `posts`, event = `likes` (reactions)
**Metric:** `likes.dwell_ms`, the viewing time before the like, in milliseconds
**Failure:** a reaction removed as spam (`reaction_status = 'removed' AND removal_reason = 'Spam detected'`), the same definition the Unit 3 audit used
**Region:** `likes.client_country`, the country the reaction came from

Queries are in [`queries/unit4/q4_1.sql`](../queries/unit4/q4_1.sql) and [`queries/unit4/q4_2.sql`](../queries/unit4/q4_2.sql). The leadership breakdown is in [`unit4-finding.md`](unit4-finding.md).

## Task 4.1: Measure the platform

### What the queries returned

**Baseline (4.1-1).** 200 reactions, 30 distinct users, 13 distinct posts. Total dwell 3,628,190 ms, average 18,141 ms, maximum 70,860 ms. The minimum is 0, which should not be possible for a like that counted. The follow-up (4.1-1b) groups by status and shows why: all 34 removed reactions have `dwell_ms = 0`, and no active or flagged reaction does. Removal zeroes the metric. So the platform-wide average is really a blend of 166 measured values and 34 placeholders, and the honest average for counted reactions is closer to 21,900 ms. That is a second data-quality finding on top of the Unit 3 one, and it means any dwell-time average that includes removed rows understates engagement by about 17 percent.

**Per producer (4.1-2).** Volume runs from 21 reactions on Post_06 down to 6 on Post_04. Two posts, Post_14 and Post_15, do not appear at all. They have no reactions, and `GROUP BY` can only make a group out of rows that exist, so a per-producer report built from the event table alone silently drops producers with zero events. Average dwell spans 11,941 ms (Post_11) to 23,057 ms (Post_05), but given the zeroing problem above, posts with more removals will look worse on dwell for reasons that have nothing to do with how long people actually read them.

**Volume threshold (4.1-3).** I set `HAVING COUNT(*) >= 10`. The reasoning: 10 reactions is 5 percent of the table and about half the median per-post volume of 16. Below 10, a single spam removal moves a post's failure rate by 10 points or more, which is the sample size talking, not the post. The filter keeps 12 of 13 posts and drops Post_04, whose 6 reactions include one spam removal. Without the threshold Post_04 would show a 16.7 percent rate and land second-worst on the platform on the strength of one event.

**Two dimensions (4.1-4).** Grouping by region and post gives 62 rows out of a possible 65 combinations. 56 of those 62 cells hold five or fewer reactions, so a per-cell average dwell is a small-sample number. This is the right shape for a regional leader to scan their own rows, but the cells should be read next to the per-post totals from 4.1-2, not instead of them.

### Write-up: who acts on this, and what the aggregate hides

The per-producer breakdown goes to the Trust and Safety lead who owns creator monetization, because the Unit 3 finding lifted a payout freeze and the follow-up question is which creators, if any, deserve a closer look. They need it by post identifier so the review can be targeted rather than platform-wide.

What the aggregates hide: the average dwell conceals its distribution, and in this dataset it conceals something specific, which is that 17 percent of the rows contribute a zero that is a side effect of moderation rather than a measurement. A count conceals who is counted. `COUNT(*)` per post counts reactions, not people, and the `COUNT(DISTINCT user_id)` column next to it shows that Post_08's 20 reactions come from 17 users while Post_10's 19 come from 12. Neither number is wrong, but they answer different questions, and a reader who sees only the first one will assume it is the second.

What I would need to see next: the per-post dwell average recomputed over non-removed reactions only, so the engagement signal is separated from the moderation signal, and a per-user view of spam removals, since two users (`user_id` 1 and 21) account for 4 of the 12 spam removals across different posts. That points at actors, not producers, and the producer breakdown cannot show it.

## Task 4.2: Build the breakdown leadership asked for

### Part A: Two numbers in one pass

The two questions answered side by side are: **how many reactions did each post receive**, and **how many of those were removed as spam**. One scan of `likes`, no `WHERE`, `GROUP BY post_id`, with `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` producing the spam column next to `COUNT(*)`. Because both live in the same row, the spam rate is just one divided by the other, and I added a third conditional column for non-spam removals at no extra cost.

Result: 12 spam removals in 200 reactions, 6.0 percent. Post_02 has 3 of the 12 (18.8 percent of its own reactions), Post_03 has 2 (15.4 percent), Post_04 has 1 but only 6 reactions. Five posts have zero. The outliers I name in the finding are Post_02 and Post_03.

### Part B: Subtotals and a grand total

The reader who needs subtotals rather than detail rows is the **regional director**. Their question is "how does my region compare to the others and to the platform," and 62 region-by-post rows do not answer it; five regional rows and one total do.

I used `GROUP BY GROUPING SETS ((client_country), ())`, which produces exactly those two levels and nothing else. The output has six rows. The five with `is_grand_total = 0` are the regional subtotals: Brazil 39 reactions and 3 spam removals, India 40 and 4, UK 40 and 1, US 38 and 3, Vietnam 43 and 1. The one row with `is_grand_total = 1` is the grand total: 200 reactions, 12 spam removals, 30 distinct users. `GROUPING(client_country)` is what tells the two apart. The grand total's region column is a synthetic `NULL`, and I label it `'ALL REGIONS'` so it cannot be confused with a real missing value. A `ROLLUP(client_country)` version is included in the file and returns the same six rows, since rolling up a single column produces the same two grouping sets.

The decision the grand total supports that the group rows do not: whether the platform-wide rate has actually changed since the Unit 3 correction, and whether any region's rate differs from it enough to matter. India's 4-in-40 (10 percent) against a platform 6 percent is the only regional number that stands out, and the grand total is what makes "stands out" measurable. The regional rows also sum to 200, which is the same check the Unit 3 finding asked for: if the pieces do not add up to the whole, something was dropped.

### Part C: A two-step pipeline

The question the pipeline answers: **what spam-removal rate should a high-volume post be measured against, and which high-volume posts sit above it?**

Step 1 (`producer_stats`) aggregates `likes` once per post into reactions and spam removals. Step 2 (`volume_cutoff`) aggregates that result to find the average reactions per post, 15.4, rounded up to 16, so "high volume" is computed from the data rather than typed in. Step 3 (`high_volume`) filters the per-post rows to those at or above the cutoff: eight posts. Step 4 (`baseline`) aggregates again over just those eight to get a pooled rate: 7 spam removals in 145 reactions, 4.8 percent. The final `SELECT` cross-joins each high-volume post to the single baseline row and expresses its rate as a multiple of it.

Post_02 is 3.9 times the high-volume baseline. Every other high-volume post is between 0 and 1.3 times. That is a cleaner statement than "Post_02 is at 18.8 percent," because it compares the post to peers with similar exposure rather than to the whole platform, which includes small posts whose rates are noise. None of this could be written as a single `GROUP BY`, because the cutoff and the baseline are both aggregates of an aggregate.

## Reflection: conditional aggregation versus separate filtered queries

Conditional aggregation puts the condition inside the aggregate instead of in the `WHERE` clause. `SUM(CASE WHEN status = 'removed' THEN 1 ELSE 0 END)` next to `COUNT(*)` reads every row once and sorts each into a bucket as it goes. The alternative is two queries, one filtered and one not, each grouped by post, stitched together afterwards in the application.

At 200 rows the difference is invisible. At a million rows it matters for three reasons. I/O: two filtered queries are two full scans of the event table, while the `CASE` version is one scan no matter how many conditions you add. On a table that does not fit in memory, that is the dominant cost. Consistency: two queries run at two moments, and on a live event table rows arrive between them, so numerator and denominator can describe different populations and the rate will not reconcile. One pass guarantees both numbers come from the same rows. Where the work lives: stitching results in application code moves the join, the null handling, and the division out of the database, where they are harder to test. Post_10 has zero spam removals; in the two-query approach it is absent from the filtered result and the application has to remember that absent means zero. In the conditional version the zero is already in the row.

The cost is that conditions must be known when the query is written. For a fixed set of statuses, which is what a quarterly report has, that is the right trade.
