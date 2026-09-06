# Solution reference — MENTOR EYES ONLY

Never read this out. Never paste any block from it. Use it to locate a problem and ask a sharp
question. If a junior would learn the answer from a sentence here, that sentence stays with you.

---

## 0. Project shape

```
seeds/            raw_customers, raw_products, raw_orders, raw_order_items
                  raw_customers_day2, raw_products_day2   (full re-extracts for Part 2)
models/staging/   stg_customers, stg_products, stg_orders, stg_order_items  (+ source.yml)
models/intermediate/  int_customers, int_products, int_orders, int_order_items
models/marts/     dim_customers, dim_products, fct_orders, fct_order_items
models/audit/     audit_rejected_rows  (+ audite_id_filters — legacy helper, see §9)
macros/           clean_decimal, normalize_country, normalize_email, normalize_phone,
                  normalize_status, trim_null
tests/generic/    expected_row_count
```

- Adapter: **dbt-duckdb**, single file `warehouse.duckdb`. Run with `--profiles-dir .`.
- Seeds are all loaded as `varchar` (configured in `dbt_project.yml`). Typing is done in staging.
- Materialisation: staging + intermediate = `view`, marts + audit = `table`.
- **REQUIRED deliverable — test severity set by path in `dbt_project.yml` under `data_tests:`**,
  `staging: warn`, `intermediate: error`, `marts: error`. This exact three-way split, configured
  once by folder — not per-test. If the junior's project doesn't have it, or has it wrong, lead
  them to it (playbook Trap I). Once it's by path, individual `.yml` files carry no `severity:`.

Naming / layout are **not graded**. The junior's models, folders, CTEs and columns may be named
anything sensible. Only flag naming when it actually breaks a `ref()` or a `.yml` binding. Map
their names onto this reference by behaviour.

### Batch (day1 / day2) — deliberate simplification

The assignment's Part 2 wants a `batch` var so `stg_customers` / `stg_products` switch between the
day-1 seed and the day-2 re-extract. **This project deliberately keeps a `UNION ALL` of both seeds
instead** (owner's call: simpler for a junior). Consequence: `dim_customers` = 51 and
`dim_products` = 33 instead of the assignment's 50 / 32. The two `expected_row_count` tests on
those dims stay red on purpose and are treated as accepted, documented divergence. Do **not** push
the junior toward the var-based design unless they raise Part 2 / snapshots.

---

## 1. stg_customers

**Purpose:** one clean, typed row per raw customer row. No joins, no dedup, no filtering.

Rules implemented:
- `customer_id` → keep as `varchar`, missing stays NULL (quarantined later in `int_customers`).
- `full_name` → trim + collapse internal whitespace; empty → NULL.
- `email` → trim, replace the `(at)` obfuscation with `@`, lowercase; empty → NULL. **Invalid but
  present addresses are kept** (the spec has them survive into the dim; `valid_email` flags them
  at `warn`).
- `phone` → digits-only, normalise Czech/international prefixes to `+420…`; unusable → NULL.
  (Not in the assignment's macro list, but the project carries it.)
- `country` → ISO-2 via the country map; unknown → NULL.
- `signup_date` → try a list of `strptime` formats, cast to `DATE`; unparseable → NULL.

Current code:
```sql
with unioned_customers as (
    select * from {{ source('raw', 'raw_customers') }}
    union all
    select * from {{ source('raw', 'raw_customers_day2') }}
),
cleaned as (
    select
        ifnull(cast(customer_id as varchar), null) as customer_id,
        nullif(trim(regexp_replace(cast(full_name as varchar), '\\s+', ' ', 'g')), '') as full_name,
        case
            when nullif(trim(cast(email as varchar)), '') is null then null
            else lower(replace(trim(cast(email as varchar)), '(at)', '@'))
        end as email,
        case
            when nullif(trim(phone), '') is null then null
            else case
                when regexp_replace(trim(phone), '[^0-9]', '', 'g') = '' then null
                when regexp_replace(trim(phone), '[^0-9]', '', 'g') like '420%' then '+' || regexp_replace(trim(phone), '[^0-9]', '', 'g')
                when regexp_replace(trim(phone), '[^0-9]', '', 'g') like '00420%' then '+' || substr(regexp_replace(trim(phone), '[^0-9]', '', 'g'), 3)
                when regexp_replace(trim(phone), '[^0-9]', '', 'g') like '00%' then '+' || substr(regexp_replace(trim(phone), '[^0-9]', '', 'g'), 3)
                when regexp_replace(trim(phone), '[^0-9]', '', 'g') like '0%' then '+' || '420' || substr(regexp_replace(trim(phone), '[^0-9]', '', 'g'), 2)
                else '+' || '420' || regexp_replace(trim(phone), '[^0-9]', '', 'g')
            end
        end as phone,
        case
            when nullif(trim(country), '') is null then null
            else upper(case
                when lower(trim(country)) in ('cz', 'czech republic', 'czechia') then 'CZ'
                when lower(trim(country)) in ('sk', 'slovakia') then 'SK'
                when lower(trim(country)) in ('de', 'germany') then 'DE'
                when lower(trim(country)) in ('at', 'austria') then 'AT'
                when lower(trim(country)) in ('pl', 'poland') then 'PL'
                when lower(trim(country)) in ('fr', 'france') then 'FR'
                when lower(trim(country)) in ('uk', 'great britain', 'united kingdom', 'england') then 'GB'
                when lower(trim(country)) in ('us', 'usa', 'united states', 'united states of america') then 'US'
                else null
            end)
        end as country,
        cast(coalesce(
            try_strptime(signup_date, '%Y-%m-%d'),
            try_strptime(signup_date, '%d.%m.%Y'),
            try_strptime(signup_date, '%d/%m/%Y'),
            try_strptime(signup_date, '%m/%d/%Y'),
            try_strptime(signup_date, '%d-%m-%Y'),
            try_strptime(signup_date, '%m-%d-%Y'),
            try_strptime(signup_date, '%Y/%m/%d'),
            try_strptime(signup_date, '%B %d, %Y'),
            try_strptime(signup_date, '%Y-%m-%dT%H:%M:%SZ')
        ) as date) as signup_date
    from unioned_customers
)
select * from cleaned
```

### The email trap (already fixed here — a junior will likely reproduce it)
An earlier version validated the address with
`regexp_extract(lower(...), '^[a-z0-9._%+\\-]+@[a-z0-9.\\-]+\\.[a-z]{2,}$', 0) = '' then null`.
In a **DuckDB single-quoted string literal, `\\` is two literal characters**, so the regex engine
receives `\\.` (escaped backslash + "any char"), which matches "a backslash then any char". No
real address contains a backslash, so the match failed and **every email became NULL**.
Symptom class: `regex-extraction`. Behavioural symptom to give: "every `email` in `stg_customers`
is NULL even though the raw seed is full of addresses." Question to ask: "what is that validation
regex actually matching, character by character, once DuckDB has parsed the string literal?"

For the day-first slash rule: put `%d/%m/%Y` **before** `%m/%d/%Y` in the coalesce so day-first
wins when both parse.

---

## 2. stg_products

**Purpose:** one clean, typed row per raw product row. No joins, no dedup.

Rules:
- `sku` → `_` → `-`, strip whitespace, uppercase. (Normalisation must happen here, before any
  downstream join or dedup.)
- `product_name` → trim + collapse whitespace; empty → NULL.
- `category` → map spelling variants onto the canonical taxonomy (`sports`, `home & kitchen`,
  `electronics`, `office`, `toys`).
- `unit_price_czk` → strip `Kč` / `CZK` / spaces, comma → dot, cast `DECIMAL(12,2)`; unparseable
  → NULL. **A negative price → NULL and flagged**; the product still stays in the dim.
- `unit` → lowercase/trim, fold `pcs/ks/piece/...` onto `pcs`.

Current code:
```sql
with unioned_products as (
    select * from {{ source('raw', 'raw_products') }}
    union all
    select * from {{ source('raw', 'raw_products_day2') }}
),
cleaned as (
    select
        upper(trim(regexp_replace(replace(cast(sku as varchar), '_', '-'), '\\s+', '', 'g'))) as sku,
        nullif(trim(regexp_replace(cast(product_name as varchar), '\\s+', ' ', 'g')), '') as product_name,
        case
            when nullif(trim(category), '') is null then null
            else case
                when trim(category) in ('sports', 'sport') then 'sports'
                when trim(category) in ('home & kitchen', 'home and kitchen', 'home & kitch', 'home and kitch', 'kitchen') then 'home & kitchen'
                when trim(category) in ('electronics', 'electronis', 'electronic') then 'electronics'
                when trim(category) in ('office') then 'office'
                when trim(category) in ('toys', 'toy') then 'toys'
                else trim(category)
            end
        end as category,
        case
            when unit_price_czk is null then null
            else try_cast(case
                when nullif(trim(lower(cast(unit_price_czk as varchar))), '') is null then null
                else replace(replace(replace(replace(trim(lower(cast(unit_price_czk as varchar))), 'kč', ''), 'czk', ''), ' ', ''), ',', '.')
            end as decimal(12,2))
        end as unit_price_czk,
        case
            when nullif(trim(cast(unit as varchar)), '') is null then null
            when lower(trim(cast(unit as varchar))) in ('pcs', 'pc', 'piece', 'pieces', 'pce', 'unit', 'units', 'ks', 'kpl', 'kom') then 'pcs'
            else lower(trim(cast(unit as varchar)))
        end as unit
    from unioned_products
)
select * from cleaned
```

**Note:** the `'\s+'` here is *also* a broken pattern (same double-backslash story as email — in a
plain literal it does not mean "whitespace"). It survives only because `trim()` handles the
leading/trailing spaces and SKUs have no *internal* spaces in this data. If a junior's SKU join
"only matches after normalization" fails, this is a place to look — symptom class
`normalization-gap`. The negative-price rule (`AB-1014` = `-249.00`) is currently **not** nulled
in staging; it is handled implicitly by the `int_products` tie-break. Assignment-strict would null
it in staging and flag it — a fair discussion point.

---

## 3. stg_orders

**Purpose:** one clean, typed row per raw order. `raw_orders` only — no day-2 file.

Rules:
- `order_id` → trim, blank → NULL.
- `customer_id` → varchar, missing stays NULL (kept downstream, not dropped).
- `order_date` → multi-format parse → `DATE`.
- `status` → **case-insensitive**, whitespace-tolerant, fold `canceled` → `cancelled`; canonical
  set `paid / completed / pending / cancelled`; anything else → NULL.
- `currency` → uppercase; blank → NULL.
- `total_amount` → money parser → `DECIMAL(12,2)`.

### The status trap (fixed here)
Earlier the comparisons were `trim(status) in ('paid', ...)` — **no `lower()`** — so `PAID`,
`Paid`, `CANCELED` fell through to `else trim(status)` and passed non-canonical values downstream.
Symptom class: `normalization-gap`. Behavioural symptom: "`int_orders` still contains `PAID`,
`Paid`, `CANCELED` — an `accepted_values` test on status would fail." Question: "list the distinct
`status` values coming out of `stg_orders` — which of them are not in the canonical four, and what
do they have in common?"

Current status expression:
```sql
case
    when nullif(trim(status), '') is null then null
    when lower(trim(status)) in ('paid', 'p a i d') then 'paid'
    when lower(trim(status)) in ('completed', 'complete') then 'completed'
    when lower(trim(status)) in ('pending') then 'pending'
    when lower(trim(status)) in ('cancelled', 'canceled') then 'cancelled'
    else null
end as status
```

---

## 4. stg_order_items

**Purpose:** one clean, typed row per raw order line. `raw_order_items` only.

Rules:
- `item_id`, `order_id` → trim, blank → NULL.
- `sku` → normalise like products (`_`→`-`, strip whitespace, uppercase).
- `quantity` → **pull the numeric token out** of values like `2 ks` or `2,5 pcs` (comma → dot
  first), cast `DECIMAL(12,2)`. `2 ks` is a valid quantity of **2**.
- `unit_price`, `line_total` → money parser.

### The quantity trap (fixed here)
Earlier: `regexp_extract(replace(trim(quantity), ',', '.'), '[-0-9.]+', 1)`. The third argument
`1` asks for **capture group 1**, but the pattern has no group, so DuckDB returns `''` and
`try_cast('')` → NULL. Result: **every quantity in `stg_order_items` was NULL** (all 284 rows).
Symptom class: `regex-extraction`. Behavioural symptom: "`quantity` is NULL for every row, even
plain values like `5`." Question: "what does the third argument to `regexp_extract` select, and
does your pattern contain what that argument is pointing at?"

Current quantity expression:
```sql
case
    when nullif(trim(cast(quantity as varchar)), '') is null then null
    else try_cast(regexp_extract(replace(trim(cast(quantity as varchar)), ',', '.'), '-?[0-9]+(\.[0-9]+)?', 0) as decimal(12,2))
end as quantity
```

The money parser (used for `unit_price`, `line_total`, and `stg_orders.total_amount`):
```sql
try_cast(
  replace(
    regexp_replace(
      lower(regexp_replace(regexp_replace(regexp_replace(trim(cast(col as varchar)),'kč','','g'),'czk','','g'),'[^0-9,.-]','','g')),
    ' ','','g'),
  ',','.')
as decimal(12,2))
```
This one handles `1 299,00`, `CZK 599`, `449,90`, `1299.00` correctly. If a junior thinks a money
value is "unparseable", have them run the raw value through step by step and check whether the
comma is being converted before the cast.

---

## 5. int_customers

**Purpose:** deduplicated entity table feeding `dim_customers`.

Steps:
1. Drop rows with NULL `customer_id` (spec: **quarantine** — they belong only in the audit model).
2. Collapse repeated `customer_id` (the day-1/day-2 reload creates two copies) → keep the most
   recent by `signup_date`.
3. **Dedup rule 2:** rows with the same normalised `email` are the same person → keep the one with
   the **lowest `customer_id`** (numeric), the rest are dropped **and written to
   `audit_rejected_rows`** with reason `duplicate_email`.

Current code:
```sql
with cleaned_customers as (
    select customer_id, full_name, email, phone, country, signup_date
    from {{ ref('stg_customers') }}
    where customer_id is not null
),
deduplicated_by_id as (
    select customer_id, full_name, email, phone, country, signup_date
    from (
        select *,
            row_number() over (partition by customer_id order by signup_date desc nulls last) as row_num
        from cleaned_customers
    )
    where row_num = 1
),
ranked_by_email as (
    select *,
        case
            when email is null then 1
            else row_number() over (partition by lower(email) order by try_cast(customer_id as bigint) asc nulls last, customer_id asc)
        end as email_rank
    from deduplicated_by_id
),
final_customers as (
    select customer_id, full_name, email, phone, country, signup_date
    from ranked_by_email
    where email_rank = 1
)
select * from final_customers
```

### Data gotchas
- Only **one** email collision in day-1: `filip.kucera@example.com` on `customer_id` 15 and 51 →
  51 is dropped and appears in the audit model.
- `customer_id` 8 and 22 each appear as **exact-duplicate rows** in `raw_customers` — collapsed by
  step 2. Assignment dedup rule 1 wants those counted in the audit model too (currently they are
  not — see §9, open item).
- The NULL-`customer_id` row ("orphan.record@example.com" / "Julia Pokorný") is quarantined by
  step 1; it *is* captured by `audit_rejected_rows` as `missing_customer_id`.
- `customer_id` 52 (Ivana Fialová) exists **only in the day-2 seed** — the reason `dim_customers`
  is 51 not 50 under the union.

---

## 6. int_products

**Purpose:** deduplicated product entity feeding `dim_products`.

Steps:
1. Drop rows with NULL `sku`.
2. **Dedup rule 3:** duplicate normalised SKUs → keep the row with the **highest parseable price**
   ("assume it's the newest list price"). Present price beats NULL; non-negative beats negative;
   `product_name` / `category` break remaining ties for determinism.

Current code:
```sql
with cleaned_products as (
    select sku, product_name, category, unit_price_czk, unit
    from {{ ref('stg_products') }}
    where sku is not null
),
ranked_products as (
    select *,
        row_number() over (
            partition by sku
            order by
                case when unit_price_czk is null then 1 else 0 end,
                case when unit_price_czk < 0 then 1 else 0 end,
                unit_price_czk desc,
                product_name, category
        ) as row_num
    from cleaned_products
),
final_products as (
    select sku, product_name, category, unit_price_czk, unit
    from ranked_products where row_num = 1
)
select * from final_products
```

### Data gotchas
- The day-1+day-2 union means most SKUs appear 2×, a few (`AB-1006`, `AB-1012`) up to 4×.
- `AB-1002`: 599 vs 279 — highest-price rule keeps 599.
- `AB-1014`: `-249` vs `249` — negative pushed last, keeps `249`.
- `AB-1018`: NULL vs `599` — NULL pushed last, keeps `599`.
- `AB-1033` exists **only in day-2** → the reason `dim_products` is 33 not 32 under the union.
- The old version of this model "deduped" by left-joining `audite_id_filters` with
  `having count(*) > 1` — that helper only ever holds NULL-id rows, so the join matched nothing
  and **no duplicates were removed**. Symptom class: `dedup-rule-mismatch` / `grain-duplication`.

---

## 7. int_orders

**Purpose:** deduplicated order entity feeding `fct_orders`.

Spec intent:
- **Dedup rule 4:** a duplicated `order_id` with conflicting statuses resolves to `cancelled` if
  *any* copy says `cancelled` (latest-known-state).
- Keep orders whose `customer_id` is missing or points to no customer → they stay in `fct_orders`
  **with a NULL customer key**; the relationship test is `warn`; the audit model counts them.

Current code:
```sql
with cleaned_orders as (
    select o.order_id, o.customer_id, o.order_date, o.status, o.currency, o.total_amount
    from {{ ref('stg_orders') }} as o
    left join (
        select a.id from {{ ref('audite_id_filters') }} as a
        where a.table_name = 'stg_orders' and a.id_name = 'order_id'
        group by a.id having count(*) > 1
    ) as duplicate_order_ids on o.order_id = duplicate_order_ids.id
    where o.order_id is not null
      and o.customer_id is not null          -- <-- DIVERGES FROM SPEC (see below)
      and duplicate_order_ids.id is null
),
preferred_order_versions as (
    select *,
        row_number() over (
            partition by order_id
            order by
                case when status = 'cancelled' then 0 when status = 'paid' then 1
                     when status = 'completed' then 2 when status = 'pending' then 3 else 4 end,
                order_date desc nulls last, total_amount desc nulls last
        ) as row_num
    from cleaned_orders
)
select order_id, customer_id, order_date, status, currency, total_amount
from preferred_order_versions where row_num = 1
```

### Open problems in this model (do not volunteer; guide if the junior looks here)
- `where o.customer_id is not null` **drops** missing-customer orders instead of keeping them with
  a NULL key. Class: `referential` / `quarantine-policy`.
- The `audite_id_filters` join is dead code (that helper never contains duplicate ids) — the real
  de-dup is the `row_number()` below it, which does work.
- `fct_orders` then filters `where status <> 'cancelled'` (see §8), so cancelled orders vanish
  entirely — contrary to the canonical status set. Between these two, `fct_orders` is 83, not 100.

---

## 8. int_order_items

**Purpose:** deduplicated, quarantined order-line entity feeding `fct_order_items`.

Steps:
1. **Dedup rule 1:** exact-duplicate lines (every column identical) → keep one; the dropped copies
   are audited (`exact_duplicate`).
2. Resolve the product by normalised `sku` against `int_products` (LEFT join). No match → **keep
   the line with a NULL product key** (`warn` relationship test, audit count).
3. Unparseable `unit_price` → **fall back to the product's list price**; if that is also NULL →
   quarantine (`unresolvable_unit_price`).
4. Quarantine and audit any line with: **no parent order** (`nonexistent_order`), or **quantity
   ≤ 0 / unparseable** (`invalid_quantity`).

Parent-order existence is checked against **`stg_orders`** (every real order), *not* `int_orders`
— so lines are not collateral damage from `int_orders`' own filtering.

Current code:
```sql
with order_items as (
    select item_id, order_id, sku, quantity, unit_price, line_total
    from {{ ref('stg_order_items') }}
),
deduplicated as (
    select item_id, order_id, sku, quantity, unit_price, line_total
    from (
        select *,
            row_number() over (
                partition by item_id, order_id, sku, quantity, unit_price, line_total
                order by item_id
            ) as dup_rank
        from order_items
    )
    where dup_rank = 1
),
resolved as (
    select
        d.item_id, d.order_id,
        case when p.sku is not null then d.sku end as sku,
        d.quantity,
        coalesce(d.unit_price, p.unit_price_czk) as unit_price,
        d.line_total
    from deduplicated as d
    left join {{ ref('int_products') }} as p on d.sku = p.sku
),
valid_order_items as (
    select item_id, order_id, sku, quantity, unit_price, line_total
    from resolved
    where item_id is not null
      and order_id in (select order_id from {{ ref('stg_orders') }} where order_id is not null)
      and quantity is not null
      and quantity > 0
      and unit_price is not null
)
select * from valid_order_items
```

### Data gotchas (the 284 → 279 arithmetic)
- `IT-5033` — the only exact-duplicate line (`ORD-2012` / `AB-1020`). 1 copy dropped.
- `IT-5100` → `ORD-9999`, `IT-5112` → `ORD-8888` — parent orders don't exist. Quarantined.
- `IT-5010` (quantity `0`), `IT-5024` (quantity `-1`) — quarantined.
- `IT-5037` (quantity `2 ks`) — **valid, kept** as quantity 2.
- `IT-5120` (`sku` `ZZ-0001`) — no product match → **kept**, NULL product key.
- `IT-5055` (`unit_price` genuinely NULL, `sku` `AB-1005`) → falls back to 249.00 → **kept**.
- `284 − 1 exact-dup − 2 nonexistent-order − 2 bad-quantity = 279`.

---

## 9. audit_rejected_rows  (and audite_id_filters)

**`audit_rejected_rows`** — one row per quarantined row: `table_name, record_key, reject_reason,
record_snapshot, audit_date`. Reason codes currently emitted:
`missing_customer_id`, `missing_or_invalid_email`, `missing_or_invalid_phone`, `missing_country`,
`duplicate_email`, `missing_sku`, `missing_or_invalid_category`, `missing_price`,
`missing_order_id`, `missing_or_invalid_order_date`, `missing_status`, `missing_total_amount`,
`exact_duplicate`, `nonexistent_order`, `invalid_quantity`, `unresolvable_unit_price`.

The order-item section recomputes the `int_order_items` quarantine logic (via an
`order_item_resolved` CTE) so every dropped line is captured with the matching reason.

**`audite_id_filters`** — a legacy helper (`table_name, id, id_name`) listing NULL identifiers. It
is still `ref`-ed by `int_orders` (dead join). The assignment actually asks for a second audit
model named **`audit_data_quality`** — one row per *issue class* with a *count*. That does not
exist yet.

### Open items vs the assignment (guide, don't push)
- `audit_data_quality` model missing.
- Exact-duplicate customer rows (ids 8, 22) and product rows not counted in the audit model.
- Some customer reasons double-count (a row missing both email and phone appears twice) — fine for
  "≥ 5 rows", not fine for the strict `seed − dedup − quarantine = mart` arithmetic.
- `audite_id_filters` should eventually be retired.

---

## 10. Marts

All four are thin: explicit column list, `select ... from {{ ref('int_<x>') }}`.
- `dim_customers`, `dim_products`, `fct_order_items` — pure pass-through.
- `fct_orders` — additionally `where status <> 'cancelled'`. **This is the divergence** that makes
  it 83 rather than 100 (combined with `int_orders` dropping missing-customer orders). Canonical
  behaviour: keep cancelled orders; keep missing-customer orders with a NULL key.

Each mart `.yml` carries: model description, `unique` + `not_null` on the primary key, column
descriptions, and an `expected_row_count` model-level test (50 / 32 / 100 / 279).

---

## 11. Macros & generic tests

Present: `clean_decimal` (money), `normalize_country`, `normalize_email`, `normalize_phone`,
`normalize_status`, `trim_null`. `normalize_email` and `normalize_status` have doc blocks; the
others do not. **The staging models currently inline their logic as raw `CASE` rather than calling
these macros** — the assignment wants the macros to be the single source of truth and to be
*exercised* by a model plus proven by a test. Open item.

Assignment's required macro names: `clean_string`, `parse_date_multi`, `parse_amount`,
`normalize_sku`, `normalize_country`, `normalize_order_status` — the project's names don't all
match.

Generic tests present: `expected_row_count(model, count)` in `tests/generic/`. Missing:
`non_negative`, `valid_email`.

Assignment also wants singular tests: line reconciliation (`line_total` ≈ `quantity * unit_price`,
`warn`, expected **6** warning rows), order reconciliation (`warn`), no-future-order-dates
(`warn`); plus schema tests `relationships` (facts → dims, `warn` per the quarantine policy) and
`accepted_values` (order status, ISO country). None of these exist yet.

---

## 12. Checkpoints (assignment "Self-check")

The `expected_row_count` mart tests are **optional** — a guardrail the junior may choose to add.
A failing count test is **not automatically a bug and not a licence to change the number**: the
junior takes the actual count to **Lana**, who confirms it's an explainable divergence or points
out the mistake (playbook Trap G).


| model | assignment | this project | why the gap |
|---|---|---|---|
| `dim_customers` | 50 | **51** | day-2-only customer `id 52`, from the kept `UNION` (accepted) |
| `dim_products` | 32 | **33** | day-2-only `AB-1033`, from the kept `UNION` (accepted) |
| `fct_orders` | 100 | **83** | `where status <> 'cancelled'` (−16) + `int_orders` drops missing-customer orders — **real bug** |
| `fct_order_items` | 279 | **279** | correct |
| `audit_rejected_rows` | ≥ 5 | ~14 | ok |
| line-reconciliation test | 6 warns | — | test not written yet |

Green today: `fct_order_items` count, all `unique`/`not_null`, staging warns.
Red today: `dim_customers` / `dim_products` counts (accepted), `fct_orders` count (real work),
plus everything not yet built (Part 2, reconciliation tests, accepted_values, relationships).

---

## 13. Part 2 (snapshots) — not started

`snap_customers` (key `customer_id`, `check` strategy on `full_name, email, country`) and
`snap_products` (key normalised `sku`, `check` on `product_name, category, unit_price_czk`,
`hard_deletes: invalidate`), both selecting from the **cleaned/deduped entity models**, plus a
`batch` var, plus three singular snapshot tests. Checkpoints: `snap_customers` 54 rows / 51
current / 3 closed; `snap_products` 37 / 32 / 5. Only relevant once the junior gets there.
