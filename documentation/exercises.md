# Copilot for Snowflake – Hands-on Exercises

Each exercise uses **one command with one prompt**. The exercises use different files from the
live demo, so you practise on fresh code.

Do exercises 2–5 **in the same chat thread**. Exercise 5 depends on it.

| # | Feature | Target |
|---|---|---|
| 1 | Inline suggestions | New file `ddl/policy/hist_policy.sql` |
| 2 | `/explain` | [procs/claim/sp_load_hist_claim.sql](../procs/claim/sp_load_hist_claim.sql) |
| 3 | `/fix` | [procs/policy/sp_load_prc_policy.sql](../procs/policy/sp_load_prc_policy.sql) |
| 4 | `/tests` | [procs/claim/sp_load_prc_claim.sql](../procs/claim/sp_load_prc_claim.sql) |
| 5 | `/compact` | The chat thread from exercises 2–4 |

---

## Exercise 1 – Inline suggestions: HIST_POLICY table DDL

**Goal:** generate a table definition from a comment that works as a spec.

1. Open `specs/policy_column_spec.csv` and `ddl/claim/hist_claim.sql` in tabs. Copilot uses open tabs as context.
2. Create `ddl/policy/hist_policy.sql` and paste the prompt below.
3. Press **Enter** after the last line and accept the suggestion with **Tab**.

**Prompt (paste as the file content):**

```sql
-- HISTORY.HIST_POLICY
-- Language : Snowflake SQL DDL
-- Purpose  : every version of every policy (SCD Type 2 on POLICY_ID)
-- Columns  : all 16 columns from specs/policy_column_spec.csv, same order, names, types,
--            lengths and NOT NULL rules, each with COMMENT = spec DESCRIPTION
--            then the 5 tracking columns from docs/snowflake_standards.md:
--            BEGIN_EFFECTIVE_DATE, END_EFFECTIVE_DATE, CURRENT_IND, LAST_UPDATE_USER, LAST_UPDATE_DATE
-- Pattern  : follow ddl/claim/hist_claim.sql (CREATE TABLE IF NOT EXISTS + table COMMENT)
-- Output   : a single CREATE TABLE statement
```

**Check:**
- [ ] 21 columns: 16 business columns, then 5 tracking columns, in that order
- [ ] `ANNUAL_PREMIUM NUMBER(18,2) NOT NULL`, with `TERMINATION_DATE`, `INSURED_SSN` and `AGENT_ID` nullable
- [ ] Every column has a `COMMENT`

---

## Exercise 2 – `/explain`: SCD Type 2 history load

**Goal:** understand an existing procedure before changing it.

1. Open `procs/claim/sp_load_hist_claim.sql`.
2. Run the command below in Copilot Chat.

**Command:**

```
/explain #file:procs/claim/sp_load_hist_claim.sql Explain how this procedure implements SCD Type 2. Walk through what happens to a claim that is (a) new, (b) changed, (c) unchanged and (d) missing from the staging file. Explain why the UPDATE must run before the INSERT, and why CLAIM_ID is not part of the HASH. Use a small before/after table example.
```

**Check:**
- [ ] All four claim scenarios are explained
- [ ] It explains that the INSERT's `LEFT JOIN … CURRENT_IND = 'Y'` picks up changed claims only because the UPDATE has already closed them
- [ ] It mentions the transaction, `ROLLBACK` and the audit row on failure

---

## Exercise 3 – `/fix`: broken POLICY processing load

**Goal:** have Copilot find and fix code that breaks the team standards.

1. Open `procs/policy/sp_load_prc_policy.sql` and `docs/snowflake_standards.md`.
2. Run the command below.

**Command:**

```
/fix #file:procs/policy/sp_load_prc_policy.sql #file:docs/snowflake_standards.md This procedure must follow the JavaScript procedure standards and the processing-table rules, and must mirror #file:procs/claim/sp_load_prc_claim.sql. List every defect with the standard it breaks, then return the corrected procedure.
```

**Check. Copilot should find these defects:**

| # | Defect | Expected fix |
|---|---|---|
| 1 | Argument used in lowercase (`p_valuation_date`) inside the JavaScript, so it is `undefined` at runtime | Use `P_VALUATION_DATE` |
| 2 | Value concatenated into the SQL, unquoted, so `2026-09-30` is evaluated as arithmetic | Pass it as a bind with `?` |
| 3 | Valuation date is not rolled to month end | `LAST_DAY(TO_DATE(?, 'YYYY-MM-DD'))` |
| 4 | `SELECT *` copies all history versions plus the 5 tracking columns | Explicit column list and `WHERE CURRENT_IND = 'Y'` |
| 5 | No `BEGIN`/`COMMIT`/`ROLLBACK` | Wrap the DML in a transaction and roll back in `catch` |
| 6 | No `ETL.LOAD_AUDIT` row, no re-throw, and it returns `"done"` | Audit on success and failure, re-throw, return `SUCCESS: inserted=<n>` |

---

## Exercise 4 – `/tests`: pytest for the CLAIM processing load

**Goal:** generate integration tests that follow the team testing standard.

1. Open `procs/claim/sp_load_prc_claim.sql` and `tests/conftest.py`.
2. Run the command below.

**Command:**

```
/tests #file:procs/claim/sp_load_prc_claim.sql #file:tests/conftest.py #file:docs/snowflake_standards.md Create tests/claim/test_sp_load_prc_claim.py following the Testing section of the standards and using the `sf` fixture. Seed HISTORY.HIST_CLAIM with rows built from specs/claim_column_spec.csv and cover: only CURRENT_IND='Y' rows are loaded; VALUATION_DATE is the last day of the month for any input date in that month; existing PRC_CLAIM rows are replaced on each run; return message and SUCCESS audit row; an invalid date rolls back and writes a FAILED audit row.
```

**Check:**
- [ ] Tests are in `tests/claim/test_sp_load_prc_claim.py` and marked `@pytest.mark.integration`
- [ ] Each test truncates and seeds through `sf`, then calls `ETL.SP_LOAD_PRC_CLAIM`
- [ ] One test passes a mid-month date (e.g. `2026-09-15`) and asserts `VALUATION_DATE = 2026-09-30`
- [ ] There are no hard-coded credentials
- [ ] Optional: `pytest tests/claim -v` runs the tests, or skips them if the Snowflake env vars are not set

---

## Exercise 5 – `/compact`: shrink the thread, keep the decisions

**Goal:** free up context in a long thread without losing the important outcomes.

1. Stay in the chat thread you used for exercises 2–4.
2. Run the command below.

**Command:**

```
/compact Keep: the team standards we applied, the 6 defects fixed in SP_LOAD_PRC_POLICY, and the test cases created for SP_LOAD_PRC_CLAIM with their file path. Drop: full code listings, explanations and example tables.
```

**Check:**
- [ ] The earlier turns are replaced by a short summary
- [ ] The summary still lists the standards, the 6 policy defects, and `tests/claim/test_sp_load_prc_claim.py`
- [ ] The full code listings are gone
- [ ] Discussion: when would you use `/compact` instead of starting a new chat?
