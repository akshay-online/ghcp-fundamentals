# Snowflake Logging and Comment Standards

Applies to every stored procedure, DDL script and SQL script in this repo.
These standards extend [snowflake_standards.md](snowflake_standards.md).

---

## 1. Procedure header comment

Every procedure body starts with this block, immediately after `AS $$`. Every field is mandatory.
Write `N/A` rather than leaving a field blank.

```javascript
//------------------------------------------------------------------------------
// PROCEDURE     : <SCHEMA>.<PROCEDURE_NAME>
// TYPE          : LOAD | SUPER | UTILITY | RECON
// DESCRIPTION   : <1-3 lines: what it populates and why>
// AUTHOR        : <Full name>
// CREATION DATE : YYYY-MM-DD
// VERSION       : <major.minor>
//------------------------------------------------------------------------------
// INPUTS
//    TABLES     : <every table/view read, SCHEMA.TABLE>
//    PARAMETERS : <P_NAME> - <meaning, format, allowed values>   or  none
// OUTPUTS
//    TABLES     : <every table written, SCHEMA.TABLE>
//    RETURNS    : <return message format, e.g. SUCCESS: inserted=<n> closed=<n>>
// CALLS         : <child procedures called, or none>
// RUN ORDER     : <JS7 job name and step number>
//------------------------------------------------------------------------------
// CHANGE LOG
// YYYY-MM-DD -- <Author> -- <JIRA-KEY> -- <what changed>
//------------------------------------------------------------------------------
```

**Rules**

| # | Rule |
|---|---|
| H1 | One header per procedure. Fields are not repeated: one `AUTHOR` and one `DESCRIPTION`. |
| H2 | `TYPE`: `LOAD` loads a single table, `SUPER` orchestrates other procedures, `UTILITY` is a reusable helper, `RECON` does reconciliation or checks. |
| H3 | `PROCEDURE` matches the `CREATE OR REPLACE PROCEDURE` name exactly. |
| H4 | `INPUTS` and `OUTPUTS` list **every** object, including the audit and log tables. |
| H5 | Do not include the database name. The environment database is set at deploy time (see L9). |
| H6 | Every code change adds a `CHANGE LOG` line with a Jira key, and bumps `VERSION` (minor for fixes, major for behaviour changes). |
| H7 | Newest change-log entries go at the bottom. Change-log entries are never edited or removed. |
| H8 | Run a spell-check over the header and log messages before raising a PR. |

---

## 2. Inline comments

| # | Rule | Example |
|---|---|---|
| C1 | Number each processing step in the order it runs, matching the `LOG_SECTION` value | `// STEP 2: close changed versions` |
| C2 | Explain *why*, not *what*. Do not restate the code. | `// DDL auto-commits, so temp tables are built before BEGIN` |
| C3 | Use `//` inside JavaScript and `--` inside SQL strings or scripts | |
| C4 | No commented-out code. Git keeps the history. | |
| C5 | Mark temporary workarounds with the Jira key that will remove them | `// TODO DATA-240: remove once source sends ISO dates` |
| C6 | Every table and column in DDL has a `COMMENT`, taken from the column spec description | `COMMENT 'Unique claim identifier'` |
| C7 | Every SQL script (DDL, tests, ad-hoc queries) starts with a 2-4 line `--` header: object, purpose, and how or when to run it | |

---

## 3. Process logging

`ETL.LOAD_AUDIT` holds **one summary row per run**. The process log holds **step-level trace rows**
for the same run, linked by `JOB_UUID`. Every `LOAD` and `SUPER` procedure must do both.

### 3.1 Log objects (owned by the recon team)

| Object | Purpose |
|---|---|
| `PROCESSING_LOG.CREATE_JOB_UUID(PROC_NAME)` | Starts a run and creates the `JOB_UUID` that later log rows attach to |
| `PROCESSING_LOG.WRITE_LOG(PROC_NAME, TARGET_TABLE, LOG_LEVEL, LOG_SECTION, LOG_TEXT)` | Writes one log row |
| `PROCESSING_LOG.JOB_LOG` | Log table: `JOB_UUID, PROC_NAME, TARGET_TABLE, LOG_LEVEL, LOG_SECTION, LOG_TEXT, LOG_USER, LOG_TS` |

`WRITE_LOG` runs its `INSERT` inside its own `BEGIN`/`COMMIT`. This makes it a scoped transaction, so log rows
survive a `ROLLBACK` in the calling procedure.

### 3.2 Log levels

| Level | Use for | Examples |
|---|---|---|
| `DEBUG` | Detail for troubleshooting | Child procedure name and parameters, generated SQL (no values) |
| `INFO` | Normal milestones, **always with row counts** | Begin, each DML step with rows affected, end |
| `WARN` | The run continues but someone should look | 0 rows in staging, DQ threshold nearly reached, `SKIPPED` run |
| `ERROR` | The run failed | Contents of the `catch` block |

### 3.3 Mandatory log events

| # | When | Level | `LOG_SECTION` | `LOG_TEXT` |
|---|---|---|---|---|
| 1 | First statement | (call) | – | `CREATE_JOB_UUID` |
| 2 | Start | `INFO` | `BEGIN` | `Begin <PROC_NAME>` + parameter values |
| 3 | Before each child call | `DEBUG` | `STEP n` | `Calling <PROC>` + parameter list |
| 4 | After each DML / child call | `INFO` | `STEP n` | `<what> rows=<n>` |
| 5 | Success | `INFO` | `END` | The same message the procedure returns |
| 6 | Failure (after `ROLLBACK`) | `ERROR` | `ERROR` | `code=<err.code> state=<err.state> msg=<err.message>` |

### 3.4 Rules

| # | Rule |
|---|---|
| L1 | Call `CREATE_JOB_UUID` before any other work. If it fails, **throw**. Do not just return a string, because JS7 must see a failed job. |
| L2 | Log only through the `log()` helper (section 4). Do not call `WRITE_LOG` directly elsewhere in the procedure. |
| L3 | Always pass log values as **binds**. Never concatenate them into the `CALL` text. |
| L4 | `LOG_SECTION` is never empty. Use `BEGIN`, `STEP n`, `END` or `ERROR`, matching the step comments (rule C1). |
| L5 | **Never log sensitive values** (columns flagged `SENSITIVE = Y` such as SSN, names, DOB, diagnosis) or SQL containing literal values. |
| L6 | Never let a logging failure hide the real error. The `ERROR` log in `catch` is itself wrapped in `try/catch`. |
| L7 | Write the `ERROR` log **after** `ROLLBACK`, then write the `FAILED` audit row, then re-throw. |
| L8 | Write messages in English, in sentence case, with no typos. Name the object as `SCHEMA.OBJECT`. |
| L9 | Never hard-code environment-specific database names (e.g. `<APP>_DEV_..._DB`) in code or log text. Use the current database set by deployment. |
| L10 | `RETURNS VARCHAR`, with no length. The return message uses the same text as the `END` log. |

---

## 4. Reference implementation

```javascript
CREATE OR REPLACE PROCEDURE ETL.SP_LOAD_HIST_CLAIM(P_LOAD_DATE VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
//------------------------------------------------------------------------------
// PROCEDURE     : ETL.SP_LOAD_HIST_CLAIM
// TYPE          : LOAD
// DESCRIPTION   : Apply SCD Type 2 changes from STG_CLAIM into HIST_CLAIM
// AUTHOR        : <Full name>
// CREATION DATE : 2026-05-12
// VERSION       : 1.2
//------------------------------------------------------------------------------
// INPUTS
//    TABLES     : STAGING.STG_CLAIM, HISTORY.HIST_CLAIM
//    PARAMETERS : P_LOAD_DATE - load date, 'YYYY-MM-DD'
// OUTPUTS
//    TABLES     : HISTORY.HIST_CLAIM, ETL.LOAD_AUDIT, PROCESSING_LOG.JOB_LOG
//    RETURNS    : SUCCESS: inserted=<n> closed=<n>
// CALLS         : PROCESSING_LOG.CREATE_JOB_UUID, PROCESSING_LOG.WRITE_LOG
// RUN ORDER     : CLAIM JS7 job, step 2
//------------------------------------------------------------------------------
// CHANGE LOG
// 2026-05-12 -- <Author> -- DATA-105 -- Initial version
// 2026-06-03 -- <Author> -- DATA-131 -- Hash-based change detection
// 2026-10-13 -- <Author> -- DATA-250 -- Process logging and new header standard
//------------------------------------------------------------------------------

var PROC_NAME = 'ETL.SP_LOAD_HIST_CLAIM';
var TARGET    = 'HISTORY.HIST_CLAIM';

function exec(sql, binds) {
  return snowflake.createStatement({ sqlText: sql, binds: binds || [] }).execute();
}

function log(level, section, text) {
  exec("CALL PROCESSING_LOG.WRITE_LOG(?, ?, ?, ?, ?)", [PROC_NAME, TARGET, level, section, text]);
}

function audit(status, rows, msg) {
  exec(
    "INSERT INTO ETL.LOAD_AUDIT (PROC_NAME, TARGET_TABLE, STATUS, ROW_COUNT, MESSAGE, RUN_USER, RUN_TS) " +
    "SELECT ?, ?, ?, ?, ?, CURRENT_USER(), CURRENT_TIMESTAMP()",
    [PROC_NAME, TARGET, status, rows, msg]
  );
}

// L1: no job UUID means no traceability, so fail the job
exec("CALL PROCESSING_LOG.CREATE_JOB_UUID(?)", [PROC_NAME]);

try {
  log('INFO', 'BEGIN', 'Begin ' + PROC_NAME + ' P_LOAD_DATE=' + P_LOAD_DATE);
  exec("BEGIN");

  // STEP 1: close current versions whose business columns changed
  var closed = /* UPDATE ... */ 0;
  log('INFO', 'STEP 1', 'Closed changed versions rows=' + closed);

  // STEP 2: insert new claims and new versions of changed claims
  var inserted = /* INSERT ... */ 0;
  log('INFO', 'STEP 2', 'Inserted new versions rows=' + inserted);

  exec("COMMIT");

  var msg = 'SUCCESS: inserted=' + inserted + ' closed=' + closed;
  audit('SUCCESS', inserted, msg);
  log('INFO', 'END', msg);
  return msg;

} catch (err) {
  exec("ROLLBACK");
  try {
    log('ERROR', 'ERROR', 'code=' + err.code + ' state=' + err.state + ' msg=' + err.message);
  } catch (logErr) { /* L6: keep the original error */ }
  audit('FAILED', 0, err.message);
  throw err;
}
$$;
```

---

## 5. Review checklist

- [ ] The header has every field, with no duplicates, and `PROCEDURE` matches the object name
- [ ] The change log has a new line with a Jira key, and `VERSION` is bumped
- [ ] `CREATE_JOB_UUID` is called first, and a failure there throws
- [ ] There is a `BEGIN` log, an `INFO` log with a row count per step, an `END` log, and an `ERROR` log written after `ROLLBACK`
- [ ] Every `LOG_SECTION` is filled in and matches its `// STEP n` comment
- [ ] No sensitive values or literal-value SQL appear in logs
- [ ] No hard-coded environment database names
- [ ] No commented-out code. Every DDL column has a `COMMENT`.
