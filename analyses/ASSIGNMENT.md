# dbt Training Assignment: E-Commerce Data Cleanroom

## Context

You've received four CSV extracts from a fictional e-commerce backoffice. As is typical of real source systems, the data is messy: duplicates, inconsistent formats, broken references, and values that don't reconcile. Your job is to build a dbt project that turns these into a trustworthy, tested mart layer.

You are graded not just on whether models build, but on whether your pipeline **catches every problem in the data and handles it according to an explicit, documented rule**. Silently dropping or silently "fixing" rows is a failure mode — every row that doesn't make it into a mart must be accounted for.

## Setup

Use **dbt Core with DuckDB** (`dbt-duckdb` adapter) — everything runs locally against a single-file database, no cloud, no credentials. The `starter/` folder contains a working `dbt_project.yml`, `profiles.yml`, and a `SETUP.md` with the exact commands and the DuckDB functions you'll want for the macros. Load the four CSVs in `seeds/` as dbt seeds. All columns are loaded as strings (already configured via `column_types` in the starter `dbt_project.yml`) — typing is *your* job, in staging, not the loader's.

Seeds provided:

| File | Grain | Approx. rows |
|---|---|---|
| `raw_customers.csv` | one row per customer (supposedly) | 54 |
| `raw_products.csv` | one row per SKU (supposedly) | 34 |
| `raw_orders.csv` | one row per order (supposedly) | 101 |
| `raw_order_items.csv` | one row per order line | 284 |

"Supposedly" is doing a lot of work in that table.

## Required project structure

```
models/
  staging/          -- stg_customers, stg_products, stg_orders, stg_order_items
                    -- 1:1 with sources; typing, trimming, normalization; no joins, no filtering
  intermediate/     -- (optional) deduplication / entity resolution steps
  marts/
    dim_customers.sql
    dim_products.sql
    fct_orders.sql
    fct_order_items.sql
  audit/
    audit_rejected_rows.sql   -- every quarantined row, with source table + reason code
    audit_data_quality.sql    -- one row per detected issue class, with a count
macros/
tests/              -- singular tests
```

Every mart and staging model needs a `.yml` with column descriptions and tests. Every macro needs a doc block explaining what it does and why it exists.

## Business rules you must implement

These rules are the spec. When your code makes a choice, it must be *this* choice, implemented in a macro or model — not an ad-hoc `CASE WHEN` buried in one file.

**Strings.** All incoming strings are trimmed and internal whitespace collapsed before anything else happens. Empty string = NULL.

**Dates.** Source dates arrive in at least four formats. Parse them all into `DATE`. For ambiguous slash-formatted dates (`03/28/2024` vs `28/03/2024`), attempt day-first interpretation, fall back to month-first if day-first is impossible. A date that cannot be parsed under any format becomes NULL — and the row is flagged in the audit model, never guessed.

**Amounts.** Monetary values arrive as `1299.00`, `449,90`, `1 299,00 Kč`, `CZK 599`, and worse. Write one parser that handles all of it. A negative price on a product is invalid → price becomes NULL, product stays in the dim, and the issue is flagged. A negative total on an order that isn't marked as a refund is flagged.

**SKUs.** SKUs must be normalized (case, surrounding whitespace, `_` vs `-` separator) before any join or dedup. Some order items reference products that only match *after* normalization — losing those joins is a grading failure.

**Countries.** Normalize to ISO-2 codes. The source contains full names, casing variants, and codes.

**Order status.** Canonical set: `paid`, `completed`, `pending`, `cancelled`. Normalize casing, whitespace, and the US spelling `canceled`. An `accepted_values` test enforces the canon.

**Deduplication rules.**
1. Exact duplicate rows (all columns identical): keep one, count the rest in the audit model.
2. Customers: after cleaning, two records with the same normalized email are the same person. Keep the record with the *lowest* customer_id; the dropped record goes to the audit model.
3. Products: after SKU normalization, duplicate SKUs are resolved by keeping the row with the **highest parseable price** (assume it's the newest list price). Document this in the model's yml.
4. Orders: a duplicated order_id with conflicting statuses resolves to `cancelled` if either record says so (latest-known-state assumption).

**Referential integrity & quarantine policy.**
- A customer row with no customer_id → **quarantine** (audit model, not the dim).
- An order referencing a nonexistent or missing customer → **keep** the order in `fct_orders` with a NULL customer key; the relationship test runs at `warn` severity and the audit model counts these.
- An order item referencing a nonexistent order → **quarantine** (a fact line without a parent is unusable).
- An order item with quantity ≤ 0 or unparseable quantity → **quarantine**. (Watch out: at least one quantity has a unit embedded in the value. `2 ks` is a valid quantity of 2, not garbage.)
- An order item with an unparseable unit price → fall back to the product's list price from `dim_products`; if that's also NULL, **quarantine**.
- An order item whose SKU has no matching product even after normalization → **keep** with NULL product key, `warn` severity, counted in audit.

**Future dates.** An order dated after today is suspicious, not fatal: keep it, flag it in audit, cover it with a `warn`-severity test.

## Macros you must write

| Macro | Signature | Behavior |
|---|---|---|
| `clean_string` | `(column)` | trim, collapse internal whitespace, empty → NULL |
| `parse_date_multi` | `(column)` | all source date formats → DATE, else NULL; day-first rule for ambiguous slashes |
| `parse_amount` | `(column)` | strip currency tokens/spaces, comma decimal → dot, cast to DECIMAL(12,2), else NULL |
| `normalize_sku` | `(column)` | trim, uppercase, `_` → `-` |
| `normalize_country` | `(column)` | map name/code variants → ISO-2, unknown → NULL |
| `normalize_order_status` | `(column)` | casing/whitespace/spelling → canonical set, unknown → NULL |

Plus two **custom generic tests** (in `tests/generic/` or `macros/`):

| Test | Behavior |
|---|---|
| `non_negative` | fails on values < 0 (apply to quantities, prices, totals) |
| `valid_email` | fails on non-NULL values not matching a basic email pattern; use `warn` severity where the spec says invalid emails survive into the dim |

Each macro must be exercised by at least one model *and* at least one test must prove it works (a seed-based unit test using dbt's `unit_tests:` config, or a singular test against known values — your choice, but say which and why).

## Tests you must ship

Schema tests: `unique` + `not_null` on every mart primary key; `relationships` from facts to dims (severities per the quarantine policy above); `accepted_values` on order status and on ISO country codes.

Singular tests:
1. **Line reconciliation**: `line_total` must equal `quantity * unit_price` (±0.01) for every row in `fct_order_items`. Run at `warn` — the mismatches are real and must surface, not block the build.
2. **Order reconciliation**: `fct_orders.total_amount` must equal the sum of its items' recomputed line values (±0.01), `warn` severity, mismatches counted in audit.
3. **No future order dates**, `warn` severity.

A full `dbt build` must finish with **zero errors**. Warnings are expected — they are how the known-bad-but-kept rows surface. A project where everything passes at `error` severity because the bad rows were silently deleted is a failed assignment.

## Part 2 — Historization with snapshots

Sources get re-extracted every night, and dims silently overwrite yesterday's truth. Part 2 adds SCD Type 2 history so the warehouse can answer "what did we believe on day 1?"

Two additional seeds simulate the next day's full re-extract: `raw_customers_day2.csv` and `raw_products_day2.csv`. They contain the same mess as day 1 **plus** changes: real value changes, entities appearing, one entity disappearing — and several changes that only *look* like changes before cleaning.

**Batch switching.** Your cleaned, deduplicated entity models (the ones feeding the dims) must select their source based on a project variable: `--vars 'batch: day1'` (default) reads the original seeds, `--vars 'batch: day2'` reads the day-2 extracts. Orders and items have no day-2 extract; only customers and products are historized.

**Snapshots.** Create two snapshots:

| Snapshot | unique_key | strategy | check_cols | hard deletes |
|---|---|---|---|---|
| `snap_customers` | customer_id | `check` | full_name, email, country | ignore (default) |
| `snap_products` | sku (normalized) | `check` | product_name, category, unit_price_czk | `hard_deletes: invalidate` |

The snapshots must select from your **cleaned and deduplicated entity models — never from raw seeds**. Think about why before you run anything: if you snapshot raw data, a source system that merely reformats a price (`249.00` → `249,00 Kč`) or fixes SKU casing creates a phantom version of a product that never actually changed. The day-2 files contain exactly such changes, on purpose. Your history must record *entity* changes, not *formatting* changes.

Also note: `unique_key` must actually be unique in what you snapshot — which is precisely why deduplication has to happen upstream of the snapshot.

**Run sequence.**

```bash
dbt run  --profiles-dir . --vars 'batch: day1'      # staging must exist before snapshots
dbt snapshot --profiles-dir . --vars 'batch: day1'
dbt run  --profiles-dir . --vars 'batch: day2'
dbt snapshot --profiles-dir . --vars 'batch: day2'
```

(`dbt snapshot` does not build its upstream refs — you'll find that out the hard way if you skip the `run`.)

**Tests on the snapshots.** Ship three singular tests, each must pass after the day-2 run:

1. **Exactly one current row per key** — for every key, exactly one row with `dbt_valid_to IS NULL`, *except* keys that were hard-deleted, which have zero.
2. **No overlapping validity windows** — for any key, the intervals `[dbt_valid_from, dbt_valid_to)` must not overlap.
3. **No phantom versions** — any two consecutive versions of the same key must differ in at least one checked column. This test failing means your snapshot is reading insufficiently cleaned data.

**Point-in-time proof.** Write one analysis (in `analyses/` or as a model) that reconstructs `dim_products` *as of the day-1 snapshot* from `snap_products`, and demonstrate that the discontinued product exists there but is absent from the current view.

### Part 2 checkpoints

- `snap_customers` after run 2: **54 rows** total, **51** current, **3** closed. Exactly **3** customers have two versions.
- `snap_products` after run 2: **37 rows** total, **32** current, **5** closed. Exactly **4** products have two versions; the fifth closed row is the hard delete.
- If you have more versions than that, you snapshotted data that wasn't clean enough. If you have fewer, look hard at how your change detection treats NULLs — two of the four product changes are NULL → value transitions.

## Self-check checkpoints

If your implementation follows the rules above, you should land on exactly:

- `dim_customers`: **50 rows**
- `dim_products`: **32 rows**
- `fct_orders`: **100 rows**
- `fct_order_items`: **279 rows**
- `audit_rejected_rows`: **≥ 5 rows**, each with a reason code
- Line-reconciliation test: **6 warning rows** (yes, six — three are direct data-entry errors, three are consequences of other problems in the same rows; be ready to explain each one in review)

If your counts differ, something in your rules differs from the spec. Find out what before the review.

## Definition of done

1. `dbt build` completes with zero errors from a clean database.
2. All checkpoint counts match.
3. `audit_rejected_rows` accounts for every row that exists in a seed but not in a mart — the arithmetic `seed rows − dedup drops − quarantined = mart rows` must hold and you must be able to demonstrate it.
4. Every business rule from this spec is traceable to a specific macro, model, or test.
5. `dbt docs generate` produces documentation with descriptions on every mart column.
6. You can walk through the lineage graph and explain each layer's responsibility in one sentence.

## Review session

Expect questions like: why does `IT-5055` show up in the reconciliation warnings even though you didn't touch its line_total? What happens to your customer dedup if two different people share an email? Which of your rules would you push back on if a stakeholder gave you this spec? Bring opinions.
