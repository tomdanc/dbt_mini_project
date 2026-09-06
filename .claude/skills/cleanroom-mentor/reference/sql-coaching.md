# SQL & CTE coaching — MENTOR EYES ONLY

The junior's core difficulty is **writing the SQL and understanding it** — especially structuring
a model as a chain of CTEs. This file is how you teach that without ever writing code. Every item
below is a set of *questions*. Never turn them into snippets.

---

## Part 1 — Teaching CTE decomposition

### The mental model to install
A dbt model = one `select` at the end, fed by a **pipeline of named steps** (CTEs). Each step:
- does **one** job (clean one thing, dedup on one key, filter one rule, join one table)
- takes a **named** input (the raw source, or a previous step)
- produces a set of rows you can inspect on its own

If a junior writes one 60-line `select` with five things happening at once, the finding is
`cte-structure`, and the coaching is decomposition — not "your query is wrong".

### Questions that build the pipeline (use before they write)
- "Say out loud what this model does to get from input to output. Now cut that sentence into
  steps — what's step 1?"
- "What does step 1 produce? Give it a name."
- "Step 2 — what's its input? Step 1's output, or the raw source again?"
- "Do any steps have to run in a particular order? Which, and why?"
- "Which step, if any, changes the number of rows? Is that on purpose?"
- "If you had to eyeball the result of just step 3, how would you do it?"

### Questions that check they hold the concept
- "In your words: what is a CTE? How's it different from nesting a sub-query inside a `from`?"
- "CTE `final` selects `from ranked` — what must be true about `ranked` for that to work?"
- "Can `ranked` refer back to `cleaned`? Can `cleaned` refer forward to `ranked`? Why not?"
- "You've got one CTE doing the dedup *and* the join *and* the filter. What breaks if you need to
  debug just the dedup?"
- "Why is five small named steps easier to trust than one big query?"

### The 'one step at a time' habit — teach it every session
- "Point the model's final `select` at just your second CTE, run it, and tell me the row count.
  Expected?"
- "Add the key column and a `count(*)` grouped by it to that CTE's output — any key with more than
  one row? Should there be?"
- "Trace `IT-5037` (or `AB-1002`, or customer 51) through each CTE. Which step touches it? Which
  step might drop it by mistake?"
- "Row count went 284 → 190 between these two CTEs. Which one did that? Did you mean it to?"
- "Open `target/compiled/…/<model>.sql` — that's the exact SQL dbt ran. Does it match what you
  think you wrote?"

### Explain-it-back (gate every 'it works')
"Narrate that CTE line by line — what each piece computes, and which spec rule it satisfies." If
they can't, they don't own it. Stay there. Don't let 'the test passed' end the conversation.

---

## Part 2 — SQL concepts this project keeps exposing

For each: the concept, how it shows up here, and questions. **No code, ever** — name the
construct, say what it does, send them to the DuckDB docs for syntax.

### Window functions vs GROUP BY
- `group by` **collapses** rows — you get one row per group and can only keep grouped keys +
  aggregates. A window function **keeps every row** and adds a value computed across a group.
- Shows up in: every `int_*` dedup. A junior who `group by`s to dedup loses the columns they need.
- Ask: "Do you want one row per key *with the other columns*, or just the key and an aggregate?"
  "If you `group by sku`, what happens to `product_name`?" "Is there a way to rank rows within a
  key without collapsing them?"

### Filtering a window-function result
- You **cannot** put a window function in a `where`. The window is computed *after* `where`. To
  filter on `row_number()` you compute it in one CTE and filter it in the next (or use `qualify`).
- Shows up in: "keep row_number = 1" attempts that won't parse or that filter the wrong thing.
- Ask: "In what order does SQL evaluate `where` vs the `select` list vs window functions?" "If the
  rank doesn't exist yet when `where` runs, where does the filter have to go?" "Have you met
  `qualify`?"

### `partition by` vs `order by` inside `over()`
- `partition by` = which rows are in the same group. `order by` = the sequence *within* the group
  that decides who's row 1.
- Shows up in: dedup keeping the wrong survivor (`dedup-rule-mismatch`).
- Ask: "What defines 'the same product' here — which column is `partition by`?" "Among duplicates,
  the spec says keep *which* one? That sentence is your `order by`." "Highest price first or
  lowest — which direction?"

### `row_number` vs `rank` vs `dense_rank`
- All number rows within a partition; they differ on ties. `row_number` always gives exactly one
  row 1.
- Ask: "If two rows tie on your ordering, how many get number 1 with each function?" "Do you want
  exactly one survivor, guaranteed?"

### NULLs in ordering
- NULLs sort first or last depending on `nulls first` / `nulls last`; the default surprises
  people.
- Shows up in: a NULL price or NULL date winning a dedup it shouldn't.
- Ask: "Where does a NULL land in your `order by` — first or last? Is that what you want for a
  missing price?"

### `NOT IN` with NULLs — the silent trap
- If the sub-query behind `NOT IN (...)` contains even one NULL, `NOT IN` returns *no rows at
  all*. `NOT EXISTS` / an anti-join don't have this problem.
- Shows up in: existence checks ("order item whose order doesn't exist") that mysteriously keep
  or drop everything.
- Ask: "Does the column in that `NOT IN` sub-query ever contain NULL?" "What does `x NOT IN (1, 2,
  NULL)` evaluate to for *any* x?" "What's a NULL-safe way to ask 'not present in that set'?"

### JOIN fan-out
- A join on a non-unique key multiplies rows. One line joined to a duplicated product row → two
  lines.
- Shows up in: `grain-duplication` in `int_order_items` / marts even though "I didn't add
  duplicates".
- Ask: "Is the key you're joining on unique on *both* sides?" "If the right table has two rows for
  that key, how many rows come back?" "What's the row count before and after this join?"

### INNER vs LEFT join (and the quarantine policy)
- `inner` drops rows with no match. `left` keeps them with NULLs on the right.
- Shows up in: order items silently disappearing because their product/order didn't match, when
  the spec says *keep with a NULL key* or *quarantine explicitly*.
- Ask: "When this join finds no match, what does the spec say should happen to that row — vanish,
  stay with a NULL key, or go to the audit model?" "Which join type produces the behaviour you
  want?"

### `where` vs `having` vs `qualify`
- `where` filters raw rows (before grouping/windows). `having` filters after `group by`. `qualify`
  filters after window functions.
- Ask: "Is the thing you're filtering on a raw column, an aggregate, or a window result? Which
  filter clause matches that?"

### `union` vs `union all`
- `union` de-duplicates the combined rows (and costs a sort). `union all` keeps everything.
- Shows up in: staging combining day-1 + day-2, audit model combining reason sets.
- Ask: "Do you want duplicate rows across the two halves removed, or kept? Which one are you
  using?" "The columns line up by *position*, not name — do your two `select`s match in order and
  type?"

### `CASE` evaluation order
- First matching `when` wins; later `when`s never fire for that row.
- Shows up in: normalization maps where a broad branch shadows a specific one.
- Ask: "For an input that matches two of your `when`s, which one takes effect?" "Is your most
  specific case above or below the general one?"

### NULL semantics generally
- `NULL = NULL` is NULL (not true). `NULL <> 'x'` is NULL. Aggregates skip NULLs. `count(*)` vs
  `count(col)` differ.
- Ask: "This `where col <> 'cancelled'` — what does it do to a row where `col` is NULL?" "Did you
  want that row kept or dropped?"

### `try_cast` / `coalesce` / `nullif`
- `try_cast` → NULL instead of erroring on bad input. `coalesce` → first non-NULL. `nullif(a,b)` →
  NULL when `a = b` (the trick for "empty string becomes NULL").
- Ask: "What do you want to happen when this string can't be parsed as a number — error, or NULL?"
  "You need blank strings to become NULL — what's the two-argument function for that?"

---

## Part 3 — dbt mechanics the junior needs

- `ref('x')` builds a dependency and resolves to the built relation; `source('raw', 'x')` points
  at a seed/source. Ask: "Is this thing you're reading another model, or a raw seed? Which
  function names that?"
- Compiled SQL lives under `target/compiled/…` after any `parse`/`run`/`build`. It's the real
  query. Send them there constantly.
- `dbt build --select <model>` (add `+` for downstream, `+` prefix for upstream) to iterate on one
  model without rebuilding the world.
- Staging/intermediate are `view`s — cheap to rebuild, always current. Marts are `table`s.
- A model is just `select … ` — no `insert`, no DDL, no `;` at the end.
- `{{ ref(...) }}` is Jinja — it renders *before* SQL runs. A Jinja error looks different from a
  SQL error; help them tell which layer failed.
