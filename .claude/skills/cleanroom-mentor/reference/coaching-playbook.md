# Coaching playbook — MENTOR EYES ONLY

For each known trap: the **symptom** you'll observe, its **error class**, what you must **not
say**, and **questions** that move the junior toward finding it themselves. Pick one question, ask
it, wait.

General rules of thumb:
- Locate precisely (layer + model + class + symptom). Frame loosely (a question, not a direction).
- If they're new to the area, ask them to explain what the model is *supposed* to do first.
- Push them to the evidence: compiled SQL, the raw seed, a `count(*)`, a `group by ... having`.
- Escalate hints only when they come back genuinely stuck, and only by one notch.

---

## Trap A — every `email` comes out NULL (`stg_customers`)

**Class:** `regex-extraction` (DuckDB string-literal escaping).
**Symptom to state:** "Every `email` in `stg_customers` is NULL, although `raw_customers` is full
of addresses — so something in the email transform is rejecting all of them."

**Do not say:** "the `\\.` is a double backslash", "use a single backslash", "DuckDB doesn't
escape", "drop the validation regex".

**Questions:**
- "Walk me through your email `CASE` branch by branch — which branch is every row landing in?"
- "Take one good address from the seed and run just the regex check on it in a scratch query.
  Pass or fail?"
- "How does DuckDB treat a backslash inside a normal single-quoted string? What does your pattern
  look like *after* the string literal is parsed, before the regex engine sees it?"
- "Does the spec even want invalid emails removed here, or kept and flagged later?"

---

## Trap B — every `quantity` comes out NULL (`stg_order_items`)

**Class:** `regex-extraction`.
**Symptom to state:** "`quantity` is NULL for every row in `stg_order_items`, even the ones that
are just `5` or `3` in the seed."

**Do not say:** "the third argument should be 0", "you're asking for a capture group that doesn't
exist", "change the group number".

**Questions:**
- "What does the third argument to `regexp_extract` mean? What is it in your call?"
- "Does your pattern contain the thing that argument is pointing at?"
- "Run your extract on the literal string `'5'` — what comes back?"
- "For `IT-5037` the raw value is `2 ks`. What's the intended result, and what does yours give?"

---

## Trap C — `status` still has `PAID` / `Paid` / `CANCELED` (`stg_orders`)

**Class:** `normalization-gap`.
**Symptom to state:** "`stg_orders.status` still contains values outside the canonical four —
`PAID`, `Paid`, `CANCELED`. An `accepted_values` test would fail on these."

**Do not say:** "add `lower()`", "you're missing case-folding", "`canceled` needs to map to
`cancelled`".

**Questions:**
- "List the distinct `status` values leaving `stg_orders`. Which are non-canonical, and what do
  those have in common?"
- "Your `CASE` compares `trim(status)` to lowercase literals — what happens when the input is
  already uppercase?"
- "The spec names an exact canonical set and one specific US spelling to fold. Which inputs in the
  data does your logic not yet cover?"
- "What should happen to a status your logic *doesn't* recognise — pass it through, or NULL it?"

---

## Trap D — a `unique` test fails on `int_products` / `int_order_items` (or `int_*`)

**Class:** `grain-duplication`, usually caused by `dedup-rule-mismatch`.
**Symptom to state:** "The `unique` test on `<key>` in `<model>` is failing — more than one row
per key is getting through, so the de-dup step isn't actually collapsing anything."

**Do not say:** "your join to the filter table matches nothing", "use `row_number()` partitioned
by the key", "the tie-break should be highest price".

**Questions:**
- "Where do the duplicate keys come from — the source, or something this pipeline does upstream?"
- "Point at the exact lines that are meant to remove duplicates. Run just that sub-query — how
  many rows does the 'duplicates' set actually contain?"
- "What does `audite_id_filters` contain? Only rows where the id is *what*? Would a join on it
  ever match a real duplicate?"
- "For products: the spec gives a specific rule for *which* of the duplicates to keep. What is it,
  and how would you express 'keep exactly one per key' in SQL?"
- "How does your ordering behave when the deciding value is NULL, or negative?"

---

## Trap E — `fct_orders` row count is low (83 vs 100)

**Class:** `referential` + `quarantine-policy` (two contributing causes).
**Symptom to state:** "`fct_orders` is short of the checkpoint. Two things upstream are removing
orders that the spec says should stay."

**Do not say:** "remove the `where status <> 'cancelled'`", "keep missing-customer orders with a
NULL key", "the filter in `int_orders` is wrong".

**Questions:**
- "Which orders are in `stg_orders` but not in `fct_orders`? Group them — is there a pattern?"
- "The spec lists a canonical status set. Is `cancelled` in it? So should a cancelled order exist
  in the fact table?"
- "Read the referential-integrity section. When an order references a customer that doesn't
  exist, what exactly is supposed to happen to that order — and to its customer key?"
- "`int_orders` has a `WHERE` clause on `customer_id`. What does it do to those orders? Is that
  what the spec asked for?"
- "If you keep those orders, what does that imply for the `relationships` test severity?"

---

## Trap F — order lines silently disappearing / wrong count (`int_order_items`)

**Class:** `quarantine-policy` (dropped but not audited) or `referential` (wrong existence check).
**Symptom to state:** "Lines are being removed from `int_order_items`, but `<some are the wrong
ones>` / `<they're not showing up in the audit model>`."

**Do not say:** the specific predicate, the reason codes, "check against `stg_orders` not
`int_orders`".

**Questions:**
- "List every reason the spec gives for removing or altering an order line. You have how many
  distinct rules?"
- "For each rule — is the affected row *dropped*, *kept as-is*, or *kept but changed*? They're not
  all the same."
- "`2 ks` — garbage, or a valid quantity? What does the spec say specifically?"
- "A line points at an order that was thrown out during *order* de-dup — is that line 'referencing
  a nonexistent order'? What's the right table to test existence against?"
- "When you drop a line, where does the spec say a record of it has to go? Does yours go there?"
- "A SKU with no product after normalisation — drop, or keep with a NULL product key?"

---

## Trap G — a mart count test fails (e.g. `dim_customers` = 51, not 50)

**Class:** `checkpoint-count`.

The `expected_row_count` tests are **optional**. If the junior added them and one goes red, the
count is a **decision point, not automatically a bug**:

- **Do not** guess whether it's fine. **Do not** tell them to change the expected number to
  whatever they got. **Do not** rule on it yourself.
- Tell them to take the *actual* number to **Lana** and ask explicitly: *"Is this an accepted
  divergence you can explain, or did I break a rule?"*

For context (so your framing is accurate — not to read out as the verdict): this project
deliberately keeps the day-1 + day-2 `UNION` instead of a `batch` var, which adds exactly one
net-new entity each (`customer_id 52`; SKU `AB-1033`) and puts the dims at 51 / 33. `fct_orders`
being under 100, by contrast, *is* real work (Trap E). But it's Lana's call to make with the
junior, model by model.

Questions to help them prepare for that conversation:
- "Which specific rows are the difference? List the `customer_id`s in your dim that aren't in the
  day-1 seed."
- "Did any change *you* made recently touch the customer dedup or filtering? Or is this the same
  number you've had since the start?"
- "What would you need to show Lana to make the case that this is expected?"

Only revisit the union-vs-var design itself if the junior starts Part 2 (snapshots need the batch
switch). Then lay out `UNION` vs a compile-time `batch` var and let them weigh it.

---

## Trap H — UNION type / column errors in the audit model or `int_*`

**Class:** `sql-error`.
**Symptom to state:** "Binder error in `<model>` — a `UNION` branch's column types (or count)
don't line up, or a column reference is ambiguous after a join."

**Do not say:** which cast to add, which alias to qualify.

**Questions:**
- "Which two `SELECT`s are being unioned there? Line their column lists up side by side — same
  order, same types?"
- "`record_snapshot` is built from a different source column in each branch. Are they all the same
  type? What does `UNION` do when they're not?"
- "That column name exists in both joined tables — how is the engine meant to know which one you
  mean?"

---

## Trap I — test severity (the required `data_tests:` block)

**Class:** `severity-config`.

The project **must** end up with severity set *by path* in `dbt_project.yml`:
**staging → `warn`, intermediate → `error`, marts → `error`.** This is a required deliverable.
Lead them there whether the symptom is "a staging test blocks my build", "everything is `warn`",
"I'm setting `severity:` on every single test", or the block simply isn't there yet.

**Do not say:** the config key, the nesting, which layer gets which level, or paste the block.

**Questions:**
- "The spec treats staging failures and mart failures differently — what's the difference, and
  why does it make sense?"
- "The known-bad-but-kept rows have to *surface without blocking the build*. Which severity is
  that? Which layer are those tests on?"
- "Right now, where is severity decided — on each individual test, or once for a whole layer?
  Which would you rather maintain?"
- "What does the `data_tests:` key in `dbt_project.yml` let you configure, and does it follow the
  same `folder: +setting` shape as the `models:` block right above it?"
- "If you set it by path, what does that let you delete from the individual `.yml` files?"

---

## Trap J — "missing artifact" findings

**Class:** `missing-artifact`.
Applies to: a staging/mart model with no `.yml`, a model `.yml` with no column descriptions, a
macro with no doc block, a required test that doesn't exist.

**Questions:**
- "The spec says *every* mart and staging model needs a `.yml` with what two things?"
- "Open your macros — which ones explain what they do and why they exist? Which don't?"
- "The 'Tests you must ship' list has how many items? Which are in your project right now?"

---

## Trap K — logic in the wrong layer

**Class:** `layering`.
**Symptom to state:** "There's a join / a filter / a dedup happening in `stg_*`" or "cleaning
logic is being repeated in a mart".

**Questions:**
- "Re-read the required-structure section. What is staging allowed to do — and explicitly *not*
  do?"
- "If you removed this join from staging, where would it naturally live?"
- "Is this mart re-deriving something an upstream layer already produced?"

---

## How to run a "check my project" pass

1. `ls` / `find` the project first — see how they laid it out, which `.yml` files exist, whether
   `dbt_project.yml` has the `data_tests:` severity block, whether `tests/` / `macros/` /
   `snapshots/` are populated.
2. `.venv/bin/dbt build --profiles-dir .`
3. For each failure, decide the class from the taxonomy. Use `reference/solution.md` to confirm
   the real cause — but only so your *question* is accurate. **Match on behaviour, not names** —
   their `stg_customers` might be called `customers_staging` and their `cleaned` CTE might be
   `step1`; that's fine, map it and move on.
4. Report each affected model on ~3 lines: **layer · class · symptom**, then **one question**.
   Use their model name. Never list a naming/style observation as a finding.
5. Separate three buckets so the junior isn't chasing a non-bug:
   - **real work** — genuine rule/logic problems (Traps A–F, H–K)
   - **required setup not done** — the `data_tests:` severity block (Trap I)
   - **for Lana** — any `expected_row_count` failure they can't tie to their own recent change;
     hand them the actual number and the question to ask her (Trap G), don't adjudicate it.
6. Stop. Do not stack the next hint until they respond.

Example of a complete, correct mentor response to "why is fct_orders failing its count test":

> `fct_orders` (marts) — **checkpoint-count**, and it traces back to two upstream causes, not one.
> Some orders that exist in `stg_orders` never reach the fact table.
> Start here: pull the list of `order_id`s that are in `stg_orders` but missing from `fct_orders`,
> and look for a pattern in their `status` and their `customer_id`. What do you see?

No code. One direction to look. One question.
