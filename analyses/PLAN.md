# Delivery plan — deadline 2026-09-01

Work the phases in order. Do not jump ahead: every phase depends on the one above it.
Tick a box only when the stated **check** passes.

---

## Where you actually are (audit taken 2026-08-31)

**Done:** seeds configured with `column_types`; 4 stage models exist with most of the cleaning
logic written inline; some stage yml with tests.

**Not started:** `macros/` is empty (0 of 6 required). `tests/` is empty (0 of 2 generic + 0 of 3
singular). No `marts/` folder at all. `audit_rejected_rows.sql` is an empty file.
No snapshots. No `batch` var. No point-in-time analysis.

**Broken right now — these will fail a build:**

1. `audit_rejected_rows.sql` is empty → dbt compile error.
2. `L02_ORDER_ITEMS.sql` is a CTE with no final `SELECT` → dbt compile error.
3. `L01_CUSTOMERS.yml` has a model-level test on `order_date` — a column that does not exist on
   the customers model → error.
4. `L01_CUSTOMERS.sql` and `L01_PRODUCTS.sql` still `UNION` the day2 seeds. That breaks `unique`
   on the PK and is the wrong mechanism for Part 2 (`batch` var is the right one).
5. `L02_CUSTOMERS.sql` selects from `source()` instead of `ref('L01_CUSTOMERS')` → skips your own
   stage layer, so none of the cleaning applies.
6. `dbt_project.yml` configures `staging:` / `intermediate:` / `marts:` but your folders are
   `01_stage` / `02_intermidiate`. Those config blocks apply to nothing.
7. `tests: +severity: warn` globally. This makes *every* test a warning, including `unique` on your
   mart primary keys. The assignment wants zero errors **with** meaningful errors still possible —
   severity belongs per-test, not project-wide.

---

## Architectural decision that drives everything

**Every L02 model keeps all its input rows and adds a `reject_reason` column.**
`NULL` = row survives. Non-null = row is quarantined or dropped by a dedup rule.

- Marts select `WHERE reject_reason IS NULL`.
- `audit_rejected_rows` unions the `WHERE reject_reason IS NOT NULL` rows from every L02 model.

Why this and not "filter in L02, rebuild rejects separately": it makes definition-of-done #3
(`seed rows − dedup drops − quarantined = mart rows`) provable with one query instead of an
argument. That sentence is what you say in the review.

Target shape:

```
01_stage/       L01_CUSTOMERS  L01_PRODUCTS  L01_ORDERS  L01_ORDER_ITEMS   (1:1, macros only)
02_intermidiate L02_CUSTOMERS  L02_PRODUCTS  L02_ORDERS  L02_ORDER_ITEMS   (+ reject_reason)
03_mart/        dim_customers  dim_products  fct_orders  fct_order_items   (filter + key join)
audit/          audit_rejected_rows  audit_data_quality
snapshots/      snap_customers  snap_products                             (from L02, never raw)
```

---

## Phase 0 — plumbing (15 min)

Measured baseline before starting: `dbt build` = **2 errors, 16 warnings**, 6 view models.

- [ ] Fix the `models:` keys in `dbt_project.yml` to match the real folder names — dbt already
      reports all 4 as "unused configuration paths", so nothing is materialized as intended.
- [ ] Add `dbt_utils` explicitly to `packages.yml` (currently only present as codegen's
      transitive dependency, while your yml tests depend on it).
- [ ] Delete `L02_ORDER_ITEMS.sql` (incomplete CTE → Parser Error). Phase 3 rewrites it.
- [ ] Delete the model-level `order_date` test from `L01_CUSTOMERS.yml` (Binder Error: that column
      does not exist on the customers model).
- [ ] Create `models/ecommerce_cleanroom/03_mart/`.
- [ ] Rename `L01_ORDERS_ITEMS` → `L01_ORDER_ITEMS` (file, yml, and the `name:` inside the yml)
      to match `raw_order_items` / `fct_order_items`.
- [ ] **Keep** `tests: +severity: warn` for now, with a TODO comment pointing at Phase 8.
      Removing it today converts the 16 existing warnings into 16 errors and destroys the signal
      we're trying to buy. Severities get set deliberately, per test, in Phase 8.

**DONE 2026-08-31** — `PASS=29 WARN=16 ERROR=0`. The `03_mart` unused-path warning is expected
until Phase 4 puts a model in that folder. The `L01_ORDERS_ITEMS` rename was dropped as cosmetic.

**Check:** `dbt build --profiles-dir .` = **0 errors**. Warnings still expected (they are real data
problems, correctly surfaced). From here on, red means *we* broke something.

## Phase 1 — the 6 macros + 2 generic tests (1 h)

`clean_string`, `parse_date_multi`, `parse_amount`, `normalize_sku`, `normalize_country`,
`normalize_order_status`, then generic tests `non_negative` and `valid_email`.
Each macro gets a doc block: what it does, why it exists, what it returns on failure.

**Check:** `dbt ls --resource-type test` shows the two generic tests are discoverable.

## Phase 2 — rewrite L01 with macros + `batch` var (1 h)

Replace all the inline `TRY_STRPTIME` / `REPLACE` chains with macro calls. Kill both UNIONs.
Customers and products pick their source from `var('batch', 'day1')`.

**Check:** row counts equal seed counts exactly — 54 / 34 / 101 / 284. One row in, one row out.

## Phase 3 — L02 dedup + quarantine (2.5 h) ← the graded core

- `L02_CUSTOMERS` — no customer_id → quarantine; exact dupes; same email → keep lowest customer_id.
- `L02_PRODUCTS` — normalized SKU dupes → keep highest parseable price; negative price → NULL + flag.
- `L02_ORDERS` — dupe order_id with conflicting status → `cancelled` wins.
- `L02_ORDER_ITEMS` — quantity parse (`2 ks` = 2); qty ≤ 0 → quarantine; orphan order → quarantine;
  unparseable unit_price → fall back to product list price, else quarantine.

**Check:** surviving row counts are 50 / 32 / 100 / 279.

## Phase 4 — marts (1 h)

Four thin models: filter `reject_reason IS NULL`, join the surrogate/foreign keys, rename to
business names. No new cleaning logic here — if you need a `CASE WHEN` in a mart, it belongs upstream.

**Check:** the four checkpoint counts again, now on the marts.

## Phase 5 — audit models (45 min)

- `audit_rejected_rows` — union of every non-null `reject_reason`, with source table + reason code.
- `audit_data_quality` — one row per issue class with a count (future dates, negative prices,
  unmatched SKUs, orders with missing customer, reconciliation mismatches).

**Check:** `audit_rejected_rows` ≥ 5 rows, and the seed−drops−quarantined arithmetic balances.

## Phase 6 — singular tests (30 min)

Line reconciliation (expect **6** warning rows), order reconciliation, no future order dates.
All three at `warn`.

**Check:** line reconciliation reports exactly 6. If it isn't 6, a Phase 3 rule is wrong.

## Phase 7 — snapshots + point-in-time proof (1.5 h)

`snap_customers` (check on full_name, email, country) and `snap_products`
(check on product_name, category, unit_price_czk, `hard_deletes: invalidate`) — both selecting
from **L02**, never from seeds. Then the four-command run sequence, then the 3 snapshot tests
(one current row per key / no overlapping windows / no phantom versions), then the analysis that
rebuilds `dim_products` as of day 1 and shows the discontinued product.

**Check:** snap_customers 54 total / 51 current / 3 closed. snap_products 37 / 32 / 5.

## Phase 8 — docs, severities, final proof (1 h)

yml descriptions on every mart column, per-test severities set deliberately (relationships to
customers at `warn`, mart PKs at `error`), `dbt docs generate`, clean-database `dbt build`,
and write the count arithmetic down somewhere you can read it out loud.

**Check:** definition of done, all 6 items.

---

## If you run out of time

Cut in this order, last thing first: Phase 8 descriptions → the point-in-time analysis →
`audit_data_quality`. **Never** cut Phase 3 or Phase 7 snapshots — those are where the marks are.


---

# Appendix — measured data profile (2026-08-31)

Derived by querying `warehouse.duckdb` directly. Don't re-derive; trust this.

## Date formats present
| Format | Example | Where |
|---|---|---|
| `%Y-%m-%d` | `2024-01-05` | both, majority |
| `%Y-%m-%dT%H:%M:%SZ` | `2024-06-14T09:22:31Z` | orders, 1 row |
| `%d/%m/%Y` | `15/08/2023` | customers, 1 |
| `%m/%d/%Y` | `03/28/2024` | orders, 1 — day-first impossible (28 > 12), falls back |
| `%-d.%-m.%Y` | `3.11.2023`, `12.3.2024` | both |
| `%B %-d, %Y` | `September 9, 2024` | customers |
| **unparseable** | `2024-13-05` (cust 27) | month 13 — looks like ISO, isn't |
| **empty** | `''` (cust 35) | |
| **future** | `2026-07-20` (cust), `2027-01-15` (order) | keep + flag |

## Amount formats present
`1299.00` · `449,90` · `1 299,00 Kč` · `1 099,00 Kč` · `249,00 Kč` · `CZK 599` · `1944,00`
· `-249.00` (product, invalid) · `-6684.00` (order total) · `0.00` · NULL
**The space is a plain U+0020**, not a non-breaking space. Verified byte by byte.

## Other columns
- **quantity**: `-1`, `0`, `1`–`5`, and `2 ks` (embedded unit — valid quantity of 2)
- **order_items unit_price**: one `1 299,00`, one NULL. `line_total` all plain.
- **country**: `AT` `CZ` `DE` `PL` `SK` · `cz` · `Czech Republic` · `czechia` · `germany` · `Slovakia`
  (note: `Czech Republic` is **not** in the `countries_eu` seed, which says `Czechia`)
- **status**: `paid` `pending` `completed` `cancelled` · `PAID` `CANCELED` `Paid ` `pending `
- **currency**: `CZK` 98, `czk` 1, `EUR` 1, NULL 1 — **the spec never mentions currency.**
  An EUR total summed with CZK totals is a real problem the spec ignores. Good "which rule would
  you push back on?" answer for the review.
- **SKU collisions after normalization**: `AB-1012`/`AB_1012` and `ab-1024`/`AB-1024`
- **invalid email**: exactly one, `marie.urban(at)example.com`

## Customer dedup arithmetic (verified)
54 source rows − 1 exact dupe (id 22) − 1 exact dupe (id 8) − 1 email dupe (id 51, keeping 15)
− 1 row with no customer_id (quarantine) = **50** = the spec's `dim_customers` checkpoint.
