# Claims – Monthly Load (DELIVERED)

**From:** Claims Operations
**Status:** Built. Jira epic DATA-101. In production since 2026-06.
**Related spec:** `specs/claim_column_spec.csv`

## Summary

Monthly CSV extract of individual claims, loaded into Snowflake through
staging → history → processing. Business key is `CLAIM_ID`.

## Decisions taken (from the PO decision log)

| # | Decision | Date |
|---|---|---|
| 1 | Business key is `CLAIM_ID` only | 2026-04-10 |
| 2 | Full file every month; changes detected by comparing all business columns | 2026-04-10 |
| 3 | Claims missing from a later file are left as-is in history (no logical delete) | 2026-04-17 |
| 4 | `CLAIMANT_NAME` and `DIAGNOSIS_CODE` masked by Snowflake masking policy on the processing table | 2026-04-24 |
| 5 | Processing table holds current records only, stamped with the valuation date (last day of month) | 2026-04-24 |
