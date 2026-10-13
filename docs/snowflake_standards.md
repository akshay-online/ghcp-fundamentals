# Snowflake Development Standards

## Naming

| Object | Pattern | Example |
|---|---|---|
| Staging table | `STAGING.STG_<ENTITY>` | `STAGING.STG_CLAIM` |
| History table | `HISTORY.HIST_<ENTITY>` | `HISTORY.HIST_CLAIM` |
| Processing table | `PROCESSING.PRC_<ENTITY>` | `PROCESSING.PRC_CLAIM` |
| Load procedure | `ETL.SP_LOAD_<LAYER>_<ENTITY>` | `ETL.SP_LOAD_HIST_CLAIM` |
| Stage | `STAGING.<ENTITY>_STAGE` | `STAGING.CLAIM_STAGE` |
| DDL file | `ddl/<entity>/<layer>_<entity>.sql` | `ddl/claim/hist_claim.sql` |
| Proc file | `procs/<entity>/sp_load_<layer>_<entity>.sql` | `procs/claim/sp_load_hist_claim.sql` |

All identifiers are UPPER_SNAKE_CASE.

## Tables

- Column names, types and lengths come from the column spec in `specs/`. Do not rename.
- Every column has a `COMMENT` taken from the spec description.
- Staging: business columns only.
- History: business columns + these 5 tracking columns, in this order:

  | Column | Type | Rule |
  |---|---|---|
  | `BEGIN_EFFECTIVE_DATE` | `DATE` | Load date of the version |
  | `END_EFFECTIVE_DATE` | `DATE` | `9999-12-31` while current; load date − 1 when closed |
  | `CURRENT_IND` | `CHAR(1)` | `Y` for the current version, otherwise `N` |
  | `LAST_UPDATE_USER` | `VARCHAR(100)` | `CURRENT_USER()` |
  | `LAST_UPDATE_DATE` | `TIMESTAMP_NTZ` | `CURRENT_TIMESTAMP()` |

- Processing: business columns + `VALUATION_DATE DATE` (last day of the reporting month),
  `LAST_UPDATE_USER`, `LAST_UPDATE_DATE`.

## JavaScript stored procedures

1. `LANGUAGE JAVASCRIPT`, `EXECUTE AS CALLER`, `RETURNS VARCHAR`.
2. **Arguments are referenced in UPPERCASE inside the JavaScript body**
   (`P_LOAD_DATE`, not `p_load_date`), whatever case they were declared in.
3. Never build SQL by concatenating values. Use `binds` with `?` placeholders.
4. Wrap all DML in `BEGIN` / `COMMIT`, with `ROLLBACK` in the `catch` block.
5. Write one row to `ETL.LOAD_AUDIT` on success and on failure.
6. Return a message with the row counts, e.g. `SUCCESS: inserted=120 closed=8`.
7. On failure, re-throw after auditing so JS7 marks the job as failed.
8. Every procedure starts with a header comment:

```
/*******************************************************************************
 * Procedure : ETL.SP_LOAD_<LAYER>_<ENTITY>
 * Purpose   : one line
 * Params    : name - meaning and format
 * Reads     : tables read
 * Writes    : tables written
 * Run order : step N of the <ENTITY> JS7 job
 * Change log: YYYY-MM-DD  JIRA-KEY  short description
 ******************************************************************************/
```

## History (SCD Type 2) rules

- Change detection compares a `HASH()` of all business columns except the key.
- Changed records: close the current row, then insert the new version.
- New records: insert as current.
- Records missing from the file: leave unchanged (no logical delete) unless the
  ticket says otherwise.

## Sensitive data

Columns flagged `SENSITIVE = Y` in the spec are masked by a Snowflake masking policy
on the processing table. Procedures load real values; masking is applied at query time.
