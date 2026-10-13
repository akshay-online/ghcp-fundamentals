# Insurance Data Loads – Snowflake (demo)

Snowflake tables and JavaScript stored procedures that load business data into a
three-layer model: **staging → history → processing**.

| Layer | Schema | Table prefix | Holds |
|---|---|---|---|
| Staging | `STAGING` | `STG_` | Raw landing of each load, business columns only |
| History | `HISTORY` | `HIST_` | Every version of a record (SCD Type 2) + 5 tracking columns |
| Processing | `PROCESSING` | `PRC_` | Current records for the valuation month + 3 audit columns |

Procedures live in schema `ETL` and are triggered by JS7 jobs in this order:
`SP_LOAD_STG_<ENTITY>` → `SP_LOAD_HIST_<ENTITY>` → `SP_LOAD_PRC_<ENTITY>`.

## Entities

| Entity | Status | Source |
|---|---|---|
| CLAIM | Built and in use | CSV file via `@STAGING.CLAIM_STAGE` |
| POLICY | In progress | CSV file via `@STAGING.POLICY_STAGE` |

## Layout

```
requirements/   business requirement write-ups
specs/          column specifications (one CSV per entity)
data/sample/    sample extracts
docs/           team standards
jira/           ticket template and drafts
ddl/            table DDL by entity; ddl/common for shared objects
procs/          stored procedures by entity
tests/          validation queries by entity
```

See `docs/snowflake_standards.md` before adding objects.
