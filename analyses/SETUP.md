# Quickstart (fully local, no cloud, no credentials)

```bash
python3 -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install dbt-duckdb                                # pulls in dbt-core + duckdb
dbt --version                                         # sanity check

dbt seed --profiles-dir .                             # loads the four CSVs into warehouse.duckdb
dbt build --profiles-dir .                            # seeds + models + tests, in DAG order
```

Layout: put the four CSVs in `seeds/`, this folder's `dbt_project.yml` and
`profiles.yml` in the project root, and create `models/`, `macros/`, `tests/`
per the assignment spec.

Inspecting your data as you work:

```bash
duckdb warehouse.duckdb                               # CLI is bundled with the pip package:
                                                      # python3 -m duckdb also works
select * from audit_rejected_rows;
```

Or point Claude Code / your editor at the file — it's just a single-file
database in the repo.

## DuckDB functions you'll want for the macros

- `try_cast(x as decimal(12,2))` — returns NULL instead of erroring; the
  backbone of `parse_amount`.
- `try_strptime(x, '%d.%m.%Y')` — NULL-on-failure date parsing; chain formats
  with `coalesce(...)` for `parse_date_multi`. Note `try_strptime` with a
  format *list* argument also exists but applies formats in order — make sure
  the order implements the spec's day-first rule.
- `regexp_replace(x, '\s+', ' ', 'g')` — the `'g'` flag matters, without it
  only the first match is replaced.
- `trim()`, `upper()`, `lower()`, `nullif(x, '')`.

## Gotchas

- `dbt build` from a dirty state can mask ref errors — when in doubt,
  delete `warehouse.duckdb` and rebuild from scratch. Definition of done
  requires a clean-database build.
- If `dbt seed` types a column as BIGINT despite the config, you edited the
  wrong `dbt_project.yml` — the seed `column_types` block is what forces
  varchar.
- Keep `warehouse.duckdb`, `target/`, and `.venv/` out of git.
