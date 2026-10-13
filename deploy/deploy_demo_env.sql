-- =============================================================================
-- Script  : deploy/deploy_demo_env.sql
-- Purpose : One-shot deployment of the full demo environment (DEMO_DB):
--           schemas, file format, stages, audit table, CLAIM + POLICY tables,
--           masking policies and all ETL load procedures.
-- Run     : Snowsight worksheet ("Run All") or SnowSQL:  snowsql -f deploy/deploy_demo_env.sql
--           Re-runnable. Masking policies require Enterprise edition or higher.
-- =============================================================================

-- USE ROLE SYSADMIN;
-- USE WAREHOUSE <YOUR_WAREHOUSE>;

-- =============================================================================
-- SECTION 1: Shared objects (ddl/common/setup_objects.sql)
-- =============================================================================

CREATE DATABASE IF NOT EXISTS DEMO_DB;
USE DATABASE DEMO_DB;

CREATE SCHEMA IF NOT EXISTS STAGING;
CREATE SCHEMA IF NOT EXISTS HISTORY;
CREATE SCHEMA IF NOT EXISTS PROCESSING;
CREATE SCHEMA IF NOT EXISTS ETL;

CREATE FILE FORMAT IF NOT EXISTS STAGING.FF_CSV_STD
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  EMPTY_FIELD_AS_NULL = TRUE
  DATE_FORMAT = 'YYYY-MM-DD'
  TRIM_SPACE = TRUE;

CREATE STAGE IF NOT EXISTS STAGING.CLAIM_STAGE
  FILE_FORMAT = STAGING.FF_CSV_STD;

CREATE STAGE IF NOT EXISTS STAGING.POLICY_STAGE
  FILE_FORMAT = STAGING.FF_CSV_STD;

CREATE TABLE IF NOT EXISTS ETL.LOAD_AUDIT (
  AUDIT_ID      NUMBER AUTOINCREMENT COMMENT 'Surrogate key',
  PROC_NAME     VARCHAR(100)  COMMENT 'Procedure that wrote the row',
  TARGET_TABLE  VARCHAR(200)  COMMENT 'Fully qualified table loaded',
  STATUS        VARCHAR(10)   COMMENT 'SUCCESS or FAILED',
  ROW_COUNT     NUMBER        COMMENT 'Rows inserted or loaded',
  MESSAGE       VARCHAR(4000) COMMENT 'Return message or error text',
  RUN_USER      VARCHAR(100)  COMMENT 'User that ran the procedure',
  RUN_TS        TIMESTAMP_NTZ COMMENT 'When the run finished'
);

-- =============================================================================
-- SECTION 2: CLAIM tables (ddl/claim/*.sql)
-- =============================================================================

CREATE TABLE IF NOT EXISTS STAGING.STG_CLAIM (
  CLAIM_ID          VARCHAR(20)   NOT NULL COMMENT 'Unique claim identifier',
  POLICY_ID         VARCHAR(20)   NOT NULL COMMENT 'Policy the claim was made against',
  CLAIM_TYPE        VARCHAR(20)   NOT NULL COMMENT 'ACCIDENT, ILLNESS, HOSPITAL, CANCER',
  CLAIM_STATUS      VARCHAR(15)   NOT NULL COMMENT 'OPEN, IN_REVIEW, PAID, DENIED, CLOSED',
  LOSS_DATE         DATE          NOT NULL COMMENT 'Date the loss event happened',
  REPORTED_DATE     DATE          NOT NULL COMMENT 'Date the claim was reported',
  CLAIM_AMOUNT      NUMBER(18,2)  NOT NULL COMMENT 'Amount claimed in USD',
  PAID_AMOUNT       NUMBER(18,2)           COMMENT 'Amount paid in USD; empty until paid',
  CLAIMANT_NAME     VARCHAR(100)  NOT NULL COMMENT 'Full name of the claimant',
  DIAGNOSIS_CODE    VARCHAR(10)            COMMENT 'ICD-10 diagnosis code',
  SOURCE_FILE_DATE  DATE          NOT NULL COMMENT 'Extract date taken from the file name'
)
COMMENT = 'Staging: monthly claims file, truncated and reloaded each run';

CREATE TABLE IF NOT EXISTS HISTORY.HIST_CLAIM (
  CLAIM_ID              VARCHAR(20)   NOT NULL COMMENT 'Unique claim identifier',
  POLICY_ID             VARCHAR(20)   NOT NULL COMMENT 'Policy the claim was made against',
  CLAIM_TYPE            VARCHAR(20)   NOT NULL COMMENT 'ACCIDENT, ILLNESS, HOSPITAL, CANCER',
  CLAIM_STATUS          VARCHAR(15)   NOT NULL COMMENT 'OPEN, IN_REVIEW, PAID, DENIED, CLOSED',
  LOSS_DATE             DATE          NOT NULL COMMENT 'Date the loss event happened',
  REPORTED_DATE         DATE          NOT NULL COMMENT 'Date the claim was reported',
  CLAIM_AMOUNT          NUMBER(18,2)  NOT NULL COMMENT 'Amount claimed in USD',
  PAID_AMOUNT           NUMBER(18,2)           COMMENT 'Amount paid in USD; empty until paid',
  CLAIMANT_NAME         VARCHAR(100)  NOT NULL COMMENT 'Full name of the claimant',
  DIAGNOSIS_CODE        VARCHAR(10)            COMMENT 'ICD-10 diagnosis code',
  SOURCE_FILE_DATE      DATE          NOT NULL COMMENT 'Extract date taken from the file name',
  BEGIN_EFFECTIVE_DATE  DATE          NOT NULL COMMENT 'Load date this version became valid',
  END_EFFECTIVE_DATE    DATE          NOT NULL COMMENT '9999-12-31 while current; load date - 1 when closed',
  CURRENT_IND           CHAR(1)       NOT NULL COMMENT 'Y = current version, N = closed',
  LAST_UPDATE_USER      VARCHAR(100)  NOT NULL COMMENT 'User that last wrote the row',
  LAST_UPDATE_DATE      TIMESTAMP_NTZ NOT NULL COMMENT 'When the row was last written'
)
COMMENT = 'History: all versions of each claim, SCD Type 2 on CLAIM_ID';

CREATE TABLE IF NOT EXISTS PROCESSING.PRC_CLAIM (
  CLAIM_ID          VARCHAR(20)   NOT NULL COMMENT 'Unique claim identifier',
  POLICY_ID         VARCHAR(20)   NOT NULL COMMENT 'Policy the claim was made against',
  CLAIM_TYPE        VARCHAR(20)   NOT NULL COMMENT 'ACCIDENT, ILLNESS, HOSPITAL, CANCER',
  CLAIM_STATUS      VARCHAR(15)   NOT NULL COMMENT 'OPEN, IN_REVIEW, PAID, DENIED, CLOSED',
  LOSS_DATE         DATE          NOT NULL COMMENT 'Date the loss event happened',
  REPORTED_DATE     DATE          NOT NULL COMMENT 'Date the claim was reported',
  CLAIM_AMOUNT      NUMBER(18,2)  NOT NULL COMMENT 'Amount claimed in USD',
  PAID_AMOUNT       NUMBER(18,2)           COMMENT 'Amount paid in USD; empty until paid',
  CLAIMANT_NAME     VARCHAR(100)  NOT NULL COMMENT 'Full name of the claimant (masked)',
  DIAGNOSIS_CODE    VARCHAR(10)            COMMENT 'ICD-10 diagnosis code (masked)',
  SOURCE_FILE_DATE  DATE          NOT NULL COMMENT 'Extract date taken from the file name',
  VALUATION_DATE    DATE          NOT NULL COMMENT 'Last day of the reporting month',
  LAST_UPDATE_USER  VARCHAR(100)  NOT NULL COMMENT 'User that loaded the row',
  LAST_UPDATE_DATE  TIMESTAMP_NTZ NOT NULL COMMENT 'When the row was loaded'
)
COMMENT = 'Processing: current claims for the valuation month';

CREATE TABLE IF NOT EXISTS PROCESSING.PRC_CLAIM_SUMMARY (
  VALUATION_DATE      DATE          NOT NULL COMMENT 'Last day of the reporting month',
  PRODUCT_CODE        VARCHAR(10)   NOT NULL COMMENT 'Product of the policy as of the valuation date',
  STATE_CODE          VARCHAR(2)    NOT NULL COMMENT 'Issue state of the policy as of the valuation date',
  CLAIM_TYPE          VARCHAR(20)   NOT NULL COMMENT 'ACCIDENT, ILLNESS, HOSPITAL, CANCER',
  AGING_BUCKET        VARCHAR(10)   NOT NULL COMMENT 'Days since reported for open claims: 000-030, 031-090, 091-180, 181+; SETTLED otherwise',
  CLAIM_COUNT         NUMBER(18,0)  NOT NULL COMMENT 'Claims in the group',
  OPEN_CLAIM_COUNT    NUMBER(18,0)  NOT NULL COMMENT 'Claims with status OPEN or IN_REVIEW',
  INCURRED_AMOUNT     NUMBER(18,2)  NOT NULL COMMENT 'Sum of CLAIM_AMOUNT in USD',
  PAID_AMOUNT         NUMBER(18,2)  NOT NULL COMMENT 'Sum of PAID_AMOUNT in USD',
  OUTSTANDING_AMOUNT  NUMBER(18,2)  NOT NULL COMMENT 'Unpaid amount on open claims in USD',
  DENIAL_RATE         NUMBER(9,4)   NOT NULL COMMENT 'Share of claims with status DENIED',
  LAST_UPDATE_USER    VARCHAR(100)  NOT NULL COMMENT 'User that last wrote the row',
  LAST_UPDATE_DATE    TIMESTAMP_NTZ NOT NULL COMMENT 'When the row was last written'
)
COMMENT = 'Processing: month-end claim summary, one row per valuation month and dimension group';

-- =============================================================================
-- SECTION 3: POLICY tables (built from specs/policy_column_spec.csv;
--            ddl/policy/ is empty in the repo)
-- =============================================================================

CREATE TABLE IF NOT EXISTS STAGING.STG_POLICY (
  POLICY_ID           VARCHAR(20)   NOT NULL COMMENT 'Unique policy identifier from the policy admin system',
  POLICY_NUMBER       VARCHAR(30)   NOT NULL COMMENT 'Policy number printed on customer documents',
  PRODUCT_CODE        VARCHAR(10)   NOT NULL COMMENT 'Product the policy was sold under',
  POLICY_STATUS       VARCHAR(15)   NOT NULL COMMENT 'Current status: ACTIVE, LAPSED, REINSTATED, TERMINATED',
  ISSUE_DATE          DATE          NOT NULL COMMENT 'Date the policy was issued',
  EFFECTIVE_DATE      DATE          NOT NULL COMMENT 'Date coverage started',
  TERMINATION_DATE    DATE                   COMMENT 'Date coverage ended; empty while in force',
  ANNUAL_PREMIUM      NUMBER(18,2)  NOT NULL COMMENT 'Annualised premium in USD; zero allowed for paid-up policies',
  PAYMENT_FREQUENCY   VARCHAR(10)   NOT NULL COMMENT 'MONTHLY, QUARTERLY, ANNUAL',
  INSURED_FIRST_NAME  VARCHAR(50)   NOT NULL COMMENT 'First name of the insured person',
  INSURED_LAST_NAME   VARCHAR(50)   NOT NULL COMMENT 'Last name of the insured person',
  INSURED_DOB         DATE          NOT NULL COMMENT 'Date of birth of the insured person',
  INSURED_SSN         VARCHAR(11)            COMMENT 'Social security number of the insured person',
  STATE_CODE          VARCHAR(2)    NOT NULL COMMENT '2-letter US state where the policy was issued',
  AGENT_ID            VARCHAR(15)            COMMENT 'Writing agent identifier',
  SOURCE_FILE_DATE    DATE          NOT NULL COMMENT 'Extract date taken from the file name'
)
COMMENT = 'Staging: monthly policy file, truncated and reloaded each run';

CREATE TABLE IF NOT EXISTS HISTORY.HIST_POLICY (
  POLICY_ID             VARCHAR(20)   NOT NULL COMMENT 'Unique policy identifier from the policy admin system',
  POLICY_NUMBER         VARCHAR(30)   NOT NULL COMMENT 'Policy number printed on customer documents',
  PRODUCT_CODE          VARCHAR(10)   NOT NULL COMMENT 'Product the policy was sold under',
  POLICY_STATUS         VARCHAR(15)   NOT NULL COMMENT 'Current status: ACTIVE, LAPSED, REINSTATED, TERMINATED',
  ISSUE_DATE            DATE          NOT NULL COMMENT 'Date the policy was issued',
  EFFECTIVE_DATE        DATE          NOT NULL COMMENT 'Date coverage started',
  TERMINATION_DATE      DATE                   COMMENT 'Date coverage ended; empty while in force',
  ANNUAL_PREMIUM        NUMBER(18,2)  NOT NULL COMMENT 'Annualised premium in USD; zero allowed for paid-up policies',
  PAYMENT_FREQUENCY     VARCHAR(10)   NOT NULL COMMENT 'MONTHLY, QUARTERLY, ANNUAL',
  INSURED_FIRST_NAME    VARCHAR(50)   NOT NULL COMMENT 'First name of the insured person',
  INSURED_LAST_NAME     VARCHAR(50)   NOT NULL COMMENT 'Last name of the insured person',
  INSURED_DOB           DATE          NOT NULL COMMENT 'Date of birth of the insured person',
  INSURED_SSN           VARCHAR(11)            COMMENT 'Social security number of the insured person',
  STATE_CODE            VARCHAR(2)    NOT NULL COMMENT '2-letter US state where the policy was issued',
  AGENT_ID              VARCHAR(15)            COMMENT 'Writing agent identifier',
  SOURCE_FILE_DATE      DATE          NOT NULL COMMENT 'Extract date taken from the file name',
  BEGIN_EFFECTIVE_DATE  DATE          NOT NULL COMMENT 'Load date this version became valid',
  END_EFFECTIVE_DATE    DATE          NOT NULL COMMENT '9999-12-31 while current; load date - 1 when closed',
  CURRENT_IND           CHAR(1)       NOT NULL COMMENT 'Y = current version, N = closed',
  LAST_UPDATE_USER      VARCHAR(100)  NOT NULL COMMENT 'User that last wrote the row',
  LAST_UPDATE_DATE      TIMESTAMP_NTZ NOT NULL COMMENT 'When the row was last written'
)
COMMENT = 'History: all versions of each policy, SCD Type 2 on POLICY_ID';

CREATE TABLE IF NOT EXISTS PROCESSING.PRC_POLICY (
  POLICY_ID           VARCHAR(20)   NOT NULL COMMENT 'Unique policy identifier from the policy admin system',
  POLICY_NUMBER       VARCHAR(30)   NOT NULL COMMENT 'Policy number printed on customer documents',
  PRODUCT_CODE        VARCHAR(10)   NOT NULL COMMENT 'Product the policy was sold under',
  POLICY_STATUS       VARCHAR(15)   NOT NULL COMMENT 'Current status: ACTIVE, LAPSED, REINSTATED, TERMINATED',
  ISSUE_DATE          DATE          NOT NULL COMMENT 'Date the policy was issued',
  EFFECTIVE_DATE      DATE          NOT NULL COMMENT 'Date coverage started',
  TERMINATION_DATE    DATE                   COMMENT 'Date coverage ended; empty while in force',
  ANNUAL_PREMIUM      NUMBER(18,2)  NOT NULL COMMENT 'Annualised premium in USD; zero allowed for paid-up policies',
  PAYMENT_FREQUENCY   VARCHAR(10)   NOT NULL COMMENT 'MONTHLY, QUARTERLY, ANNUAL',
  INSURED_FIRST_NAME  VARCHAR(50)   NOT NULL COMMENT 'First name of the insured person (masked)',
  INSURED_LAST_NAME   VARCHAR(50)   NOT NULL COMMENT 'Last name of the insured person (masked)',
  INSURED_DOB         DATE          NOT NULL COMMENT 'Date of birth of the insured person (masked)',
  INSURED_SSN         VARCHAR(11)            COMMENT 'Social security number of the insured person (masked)',
  STATE_CODE          VARCHAR(2)    NOT NULL COMMENT '2-letter US state where the policy was issued',
  AGENT_ID            VARCHAR(15)            COMMENT 'Writing agent identifier',
  SOURCE_FILE_DATE    DATE          NOT NULL COMMENT 'Extract date taken from the file name',
  VALUATION_DATE      DATE          NOT NULL COMMENT 'Last day of the reporting month',
  LAST_UPDATE_USER    VARCHAR(100)  NOT NULL COMMENT 'User that loaded the row',
  LAST_UPDATE_DATE    TIMESTAMP_NTZ NOT NULL COMMENT 'When the row was loaded'
)
COMMENT = 'Processing: current policies for the valuation month';

-- =============================================================================
-- SECTION 4: Masking policies (ddl/claim/masking_claim.sql + POLICY sensitive columns)
-- FORCE lets the script be re-run when a policy is already attached.
-- =============================================================================

CREATE MASKING POLICY IF NOT EXISTS PROCESSING.MASK_PII_STRING AS (VAL VARCHAR)
RETURNS VARCHAR ->
  CASE
    WHEN IS_ROLE_IN_SESSION('PII_READER') THEN VAL
    ELSE '***MASKED***'
  END;

CREATE MASKING POLICY IF NOT EXISTS PROCESSING.MASK_PII_DATE AS (VAL DATE)
RETURNS DATE ->
  CASE
    WHEN IS_ROLE_IN_SESSION('PII_READER') THEN VAL
    ELSE NULL
  END;

ALTER TABLE PROCESSING.PRC_CLAIM MODIFY COLUMN CLAIMANT_NAME
  SET MASKING POLICY PROCESSING.MASK_PII_STRING FORCE;
ALTER TABLE PROCESSING.PRC_CLAIM MODIFY COLUMN DIAGNOSIS_CODE
  SET MASKING POLICY PROCESSING.MASK_PII_STRING FORCE;

ALTER TABLE PROCESSING.PRC_POLICY MODIFY COLUMN INSURED_FIRST_NAME
  SET MASKING POLICY PROCESSING.MASK_PII_STRING FORCE;
ALTER TABLE PROCESSING.PRC_POLICY MODIFY COLUMN INSURED_LAST_NAME
  SET MASKING POLICY PROCESSING.MASK_PII_STRING FORCE;
ALTER TABLE PROCESSING.PRC_POLICY MODIFY COLUMN INSURED_SSN
  SET MASKING POLICY PROCESSING.MASK_PII_STRING FORCE;
ALTER TABLE PROCESSING.PRC_POLICY MODIFY COLUMN INSURED_DOB
  SET MASKING POLICY PROCESSING.MASK_PII_DATE FORCE;

-- =============================================================================
-- SECTION 5: CLAIM procedures (procs/claim/*.sql)
-- =============================================================================

CREATE OR REPLACE PROCEDURE ETL.SP_LOAD_STG_CLAIM()
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
/*******************************************************************************
 * Procedure : ETL.SP_LOAD_STG_CLAIM
 * Purpose   : Reload STAGING.STG_CLAIM from the claim files on the stage
 * Params    : none
 * Reads     : @STAGING.CLAIM_STAGE (files matching claim_YYYYMMDD.csv)
 * Writes    : STAGING.STG_CLAIM, ETL.LOAD_AUDIT
 * Run order : step 1 of the CLAIM JS7 job
 * Change log: 2026-05-12  DATA-104  Initial version
 ******************************************************************************/

var PROC_NAME = 'ETL.SP_LOAD_STG_CLAIM';
var TARGET    = 'STAGING.STG_CLAIM';

function exec(sql, binds) {
  return snowflake.createStatement({ sqlText: sql, binds: binds || [] }).execute();
}

function audit(status, rows, msg) {
  exec(
    "INSERT INTO ETL.LOAD_AUDIT (PROC_NAME, TARGET_TABLE, STATUS, ROW_COUNT, MESSAGE, RUN_USER, RUN_TS) " +
    "SELECT ?, ?, ?, ?, ?, CURRENT_USER(), CURRENT_TIMESTAMP()",
    [PROC_NAME, TARGET, status, rows, msg]
  );
}

try {
  exec("BEGIN");

  exec("DELETE FROM STAGING.STG_CLAIM");

  exec(
    "COPY INTO STAGING.STG_CLAIM " +
    "FROM @STAGING.CLAIM_STAGE " +
    "FILE_FORMAT = (FORMAT_NAME = 'STAGING.FF_CSV_STD') " +
    "PATTERN = '.*claim_[0-9]{8}[.]csv' " +
    "ON_ERROR = 'ABORT_STATEMENT'"
  );

  var rs = exec("SELECT COUNT(*) FROM STAGING.STG_CLAIM");
  rs.next();
  var loaded = rs.getColumnValue(1);

  exec("COMMIT");

  var msg = 'SUCCESS: loaded=' + loaded;
  audit('SUCCESS', loaded, msg);
  return msg;

} catch (err) {
  exec("ROLLBACK");
  audit('FAILED', 0, err.message);
  throw err;
}
$$;

CREATE OR REPLACE PROCEDURE ETL.SP_LOAD_HIST_CLAIM(P_LOAD_DATE VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
/*******************************************************************************
 * Procedure : ETL.SP_LOAD_HIST_CLAIM
 * Purpose   : Apply SCD Type 2 changes from STG_CLAIM into HIST_CLAIM
 * Params    : P_LOAD_DATE - load date, 'YYYY-MM-DD'
 * Reads     : STAGING.STG_CLAIM, HISTORY.HIST_CLAIM
 * Writes    : HISTORY.HIST_CLAIM, ETL.LOAD_AUDIT
 * Run order : step 2 of the CLAIM JS7 job
 * Change log: 2026-05-12  DATA-105  Initial version
 *             2026-06-03  DATA-131  Hash-based change detection
 ******************************************************************************/

var PROC_NAME = 'ETL.SP_LOAD_HIST_CLAIM';
var TARGET    = 'HISTORY.HIST_CLAIM';

function exec(sql, binds) {
  return snowflake.createStatement({ sqlText: sql, binds: binds || [] }).execute();
}

function rowsAffected(rs) {
  rs.next();
  return rs.getColumnValue(1);
}

function audit(status, rows, msg) {
  exec(
    "INSERT INTO ETL.LOAD_AUDIT (PROC_NAME, TARGET_TABLE, STATUS, ROW_COUNT, MESSAGE, RUN_USER, RUN_TS) " +
    "SELECT ?, ?, ?, ?, ?, CURRENT_USER(), CURRENT_TIMESTAMP()",
    [PROC_NAME, TARGET, status, rows, msg]
  );
}

try {
  exec("BEGIN");

  // 1. Close current versions whose business columns changed
  var closed = rowsAffected(exec(
    "UPDATE HISTORY.HIST_CLAIM h " +
    "SET END_EFFECTIVE_DATE = DATEADD(DAY, -1, TO_DATE(?, 'YYYY-MM-DD')), " +
    "    CURRENT_IND        = 'N', " +
    "    LAST_UPDATE_USER   = CURRENT_USER(), " +
    "    LAST_UPDATE_DATE   = CURRENT_TIMESTAMP() " +
    "FROM STAGING.STG_CLAIM s " +
    "WHERE h.CLAIM_ID = s.CLAIM_ID " +
    "  AND h.CURRENT_IND = 'Y' " +
    "  AND HASH(h.POLICY_ID, h.CLAIM_TYPE, h.CLAIM_STATUS, h.LOSS_DATE, h.REPORTED_DATE, " +
    "           h.CLAIM_AMOUNT, h.PAID_AMOUNT, h.CLAIMANT_NAME, h.DIAGNOSIS_CODE) " +
    "   <> HASH(s.POLICY_ID, s.CLAIM_TYPE, s.CLAIM_STATUS, s.LOSS_DATE, s.REPORTED_DATE, " +
    "           s.CLAIM_AMOUNT, s.PAID_AMOUNT, s.CLAIMANT_NAME, s.DIAGNOSIS_CODE)",
    [P_LOAD_DATE]
  ));

  // 2. Insert new claims and new versions of changed claims
  //    (any staging row without a current history row)
  var inserted = rowsAffected(exec(
    "INSERT INTO HISTORY.HIST_CLAIM (" +
    "  CLAIM_ID, POLICY_ID, CLAIM_TYPE, CLAIM_STATUS, LOSS_DATE, REPORTED_DATE, " +
    "  CLAIM_AMOUNT, PAID_AMOUNT, CLAIMANT_NAME, DIAGNOSIS_CODE, SOURCE_FILE_DATE, " +
    "  BEGIN_EFFECTIVE_DATE, END_EFFECTIVE_DATE, CURRENT_IND, LAST_UPDATE_USER, LAST_UPDATE_DATE) " +
    "SELECT s.CLAIM_ID, s.POLICY_ID, s.CLAIM_TYPE, s.CLAIM_STATUS, s.LOSS_DATE, s.REPORTED_DATE, " +
    "       s.CLAIM_AMOUNT, s.PAID_AMOUNT, s.CLAIMANT_NAME, s.DIAGNOSIS_CODE, s.SOURCE_FILE_DATE, " +
    "       TO_DATE(?, 'YYYY-MM-DD'), TO_DATE('9999-12-31'), 'Y', CURRENT_USER(), CURRENT_TIMESTAMP() " +
    "FROM STAGING.STG_CLAIM s " +
    "LEFT JOIN HISTORY.HIST_CLAIM h " +
    "  ON h.CLAIM_ID = s.CLAIM_ID AND h.CURRENT_IND = 'Y' " +
    "WHERE h.CLAIM_ID IS NULL",
    [P_LOAD_DATE]
  ));

  exec("COMMIT");

  var msg = 'SUCCESS: inserted=' + inserted + ' closed=' + closed;
  audit('SUCCESS', inserted, msg);
  return msg;

} catch (err) {
  exec("ROLLBACK");
  audit('FAILED', 0, err.message);
  throw err;
}
$$;

CREATE OR REPLACE PROCEDURE ETL.SP_LOAD_PRC_CLAIM(P_VALUATION_DATE VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
/*******************************************************************************
 * Procedure : ETL.SP_LOAD_PRC_CLAIM
 * Purpose   : Reload PRC_CLAIM with the current version of each claim
 * Params    : P_VALUATION_DATE - any date in the reporting month, 'YYYY-MM-DD';
 *             stored as the last day of that month
 * Reads     : HISTORY.HIST_CLAIM
 * Writes    : PROCESSING.PRC_CLAIM, ETL.LOAD_AUDIT
 * Run order : step 3 of the CLAIM JS7 job
 * Change log: 2026-05-12  DATA-106  Initial version
 ******************************************************************************/

var PROC_NAME = 'ETL.SP_LOAD_PRC_CLAIM';
var TARGET    = 'PROCESSING.PRC_CLAIM';

function exec(sql, binds) {
  return snowflake.createStatement({ sqlText: sql, binds: binds || [] }).execute();
}

function rowsAffected(rs) {
  rs.next();
  return rs.getColumnValue(1);
}

function audit(status, rows, msg) {
  exec(
    "INSERT INTO ETL.LOAD_AUDIT (PROC_NAME, TARGET_TABLE, STATUS, ROW_COUNT, MESSAGE, RUN_USER, RUN_TS) " +
    "SELECT ?, ?, ?, ?, ?, CURRENT_USER(), CURRENT_TIMESTAMP()",
    [PROC_NAME, TARGET, status, rows, msg]
  );
}

try {
  exec("BEGIN");

  exec("DELETE FROM PROCESSING.PRC_CLAIM");

  var inserted = rowsAffected(exec(
    "INSERT INTO PROCESSING.PRC_CLAIM (" +
    "  CLAIM_ID, POLICY_ID, CLAIM_TYPE, CLAIM_STATUS, LOSS_DATE, REPORTED_DATE, " +
    "  CLAIM_AMOUNT, PAID_AMOUNT, CLAIMANT_NAME, DIAGNOSIS_CODE, SOURCE_FILE_DATE, " +
    "  VALUATION_DATE, LAST_UPDATE_USER, LAST_UPDATE_DATE) " +
    "SELECT CLAIM_ID, POLICY_ID, CLAIM_TYPE, CLAIM_STATUS, LOSS_DATE, REPORTED_DATE, " +
    "       CLAIM_AMOUNT, PAID_AMOUNT, CLAIMANT_NAME, DIAGNOSIS_CODE, SOURCE_FILE_DATE, " +
    "       LAST_DAY(TO_DATE(?, 'YYYY-MM-DD')), CURRENT_USER(), CURRENT_TIMESTAMP() " +
    "FROM HISTORY.HIST_CLAIM " +
    "WHERE CURRENT_IND = 'Y'",
    [P_VALUATION_DATE]
  ));

  exec("COMMIT");

  var msg = 'SUCCESS: inserted=' + inserted;
  audit('SUCCESS', inserted, msg);
  return msg;

} catch (err) {
  exec("ROLLBACK");
  audit('FAILED', 0, err.message);
  throw err;
}
$$;

CREATE OR REPLACE PROCEDURE ETL.SP_LOAD_PRC_CLAIM_SUMMARY(P_VALUATION_DATE VARCHAR, P_RUN_MODE VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
/*******************************************************************************
 * Procedure : ETL.SP_LOAD_PRC_CLAIM_SUMMARY
 * Purpose   : Build the month-end claim summary from point-in-time claim and policy history
 * Params    : P_VALUATION_DATE - any date in the reporting month, 'YYYY-MM-DD';
 *                                rolled to the last day of that month
 *             P_RUN_MODE       - NORMAL  : skip if the month is already loaded
 *                                RERUN   : rebuild the month
 *                                DRY_RUN : compute everything, write nothing but the audit row
 * Reads     : HISTORY.HIST_CLAIM, HISTORY.HIST_POLICY, PROCESSING.PRC_CLAIM_SUMMARY
 * Writes    : PROCESSING.PRC_CLAIM_SUMMARY, ETL.LOAD_AUDIT
 * Run order : step 4 of the CLAIM JS7 job (after the POLICY job)
 * Change log: 2026-07-08  DATA-162  Initial version
 *             2026-08-19  DATA-187  Point-in-time policy join, orphan claim DQ check
 *             2026-09-09  DATA-201  DRY_RUN mode, hash-based MERGE update
 ******************************************************************************/

var PROC_NAME            = 'ETL.SP_LOAD_PRC_CLAIM_SUMMARY';
var TARGET               = 'PROCESSING.PRC_CLAIM_SUMMARY';
var VALID_MODES          = ['NORMAL', 'RERUN', 'DRY_RUN'];
var ORPHAN_THRESHOLD_PCT = 2;
var OPEN_STATUSES        = "('OPEN', 'IN_REVIEW')";

function exec(sql, binds) {
  return snowflake.createStatement({ sqlText: sql, binds: binds || [] }).execute();
}

function scalar(sql, binds) {
  var rs = exec(sql, binds);
  rs.next();
  return rs.getColumnValue(1);
}

function audit(status, rows, msg) {
  exec(
    "INSERT INTO ETL.LOAD_AUDIT (PROC_NAME, TARGET_TABLE, STATUS, ROW_COUNT, MESSAGE, RUN_USER, RUN_TS) " +
    "SELECT ?, ?, ?, ?, ?, CURRENT_USER(), CURRENT_TIMESTAMP()",
    [PROC_NAME, TARGET, status, rows, msg]
  );
}

var inTxn = false;

try {
  // ---------------------------------------------------------------------------
  // 1. Validate arguments
  // ---------------------------------------------------------------------------
  var runMode = (P_RUN_MODE || 'NORMAL').toUpperCase();
  if (VALID_MODES.indexOf(runMode) < 0) {
    throw new Error('Invalid P_RUN_MODE "' + P_RUN_MODE + '". Expected one of ' + VALID_MODES.join(', '));
  }

  var valDate = scalar(
    "SELECT TO_VARCHAR(LAST_DAY(TRY_TO_DATE(?, 'YYYY-MM-DD')), 'YYYY-MM-DD')",
    [P_VALUATION_DATE]
  );
  if (valDate === null) {
    throw new Error('Invalid P_VALUATION_DATE "' + P_VALUATION_DATE + '". Expected YYYY-MM-DD');
  }

  // ---------------------------------------------------------------------------
  // 2. Idempotency: NORMAL runs never overwrite a month that is already loaded
  // ---------------------------------------------------------------------------
  var existing = scalar(
    "SELECT COUNT(*) FROM PROCESSING.PRC_CLAIM_SUMMARY WHERE VALUATION_DATE = TO_DATE(?)",
    [valDate]
  );
  if (existing > 0 && runMode === 'NORMAL') {
    var skipMsg = 'SKIPPED: ' + valDate + ' already loaded (' + existing + ' rows). Use RERUN to rebuild.';
    audit('SKIPPED', 0, skipMsg);
    return skipMsg;
  }

  // ---------------------------------------------------------------------------
  // 3. Working sets. Temp tables are DDL, which auto-commits in Snowflake,
  //    so they are built before BEGIN.
  // ---------------------------------------------------------------------------

  // 3a. Version of each claim that was valid on the valuation date
  exec(
    "CREATE OR REPLACE TEMPORARY TABLE TMP_CLAIM_ASOF AS " +
    "WITH prm AS (SELECT TO_DATE(?) AS VDATE) " +
    "SELECT c.CLAIM_ID, c.POLICY_ID, c.CLAIM_TYPE, c.CLAIM_STATUS, c.REPORTED_DATE, " +
    "       c.CLAIM_AMOUNT, c.PAID_AMOUNT, prm.VDATE " +
    "FROM HISTORY.HIST_CLAIM c " +
    "CROSS JOIN prm " +
    "WHERE prm.VDATE BETWEEN c.BEGIN_EFFECTIVE_DATE AND c.END_EFFECTIVE_DATE " +
    "  AND c.REPORTED_DATE <= prm.VDATE " +
    "QUALIFY ROW_NUMBER() OVER (PARTITION BY c.CLAIM_ID " +
    "                           ORDER BY c.BEGIN_EFFECTIVE_DATE DESC, c.LAST_UPDATE_DATE DESC) = 1",
    [valDate]
  );

  // 3b. Attach the policy version valid on the same date, aging bucket and outstanding amount
  exec(
    "CREATE OR REPLACE TEMPORARY TABLE TMP_CLAIM_ENRICHED AS " +
    "SELECT c.CLAIM_ID, c.CLAIM_TYPE, c.CLAIM_STATUS, c.CLAIM_AMOUNT, c.PAID_AMOUNT, " +
    "       p.PRODUCT_CODE, p.STATE_CODE, " +
    "       CASE " +
    "         WHEN c.CLAIM_STATUS NOT IN " + OPEN_STATUSES + " THEN 'SETTLED' " +
    "         WHEN DATEDIFF(DAY, c.REPORTED_DATE, c.VDATE) <= 30  THEN '000-030' " +
    "         WHEN DATEDIFF(DAY, c.REPORTED_DATE, c.VDATE) <= 90  THEN '031-090' " +
    "         WHEN DATEDIFF(DAY, c.REPORTED_DATE, c.VDATE) <= 180 THEN '091-180' " +
    "         ELSE '181+' " +
    "       END AS AGING_BUCKET, " +
    "       IFF(c.CLAIM_STATUS IN " + OPEN_STATUSES + ", " +
    "           c.CLAIM_AMOUNT - COALESCE(c.PAID_AMOUNT, 0), 0) AS OUTSTANDING_AMOUNT, " +
    "       IFF(p.POLICY_ID IS NULL, 'Y', 'N') AS ORPHAN_IND " +
    "FROM TMP_CLAIM_ASOF c " +
    "LEFT JOIN HISTORY.HIST_POLICY p " +
    "  ON p.POLICY_ID = c.POLICY_ID " +
    " AND c.VDATE BETWEEN p.BEGIN_EFFECTIVE_DATE AND p.END_EFFECTIVE_DATE"
  );

  // ---------------------------------------------------------------------------
  // 4. Data quality gate: too many claims without a policy means the POLICY
  //    load is late or broken, so stop rather than publish a partial summary
  // ---------------------------------------------------------------------------
  var dq = exec("SELECT COUNT(*), COUNT_IF(ORPHAN_IND = 'Y') FROM TMP_CLAIM_ENRICHED");
  dq.next();
  var totalClaims  = dq.getColumnValue(1);
  var orphanClaims = dq.getColumnValue(2);
  var orphanPct    = totalClaims === 0 ? 0 : (orphanClaims * 100.0 / totalClaims);

  if (orphanPct > ORPHAN_THRESHOLD_PCT) {
    throw new Error('DQ failed: ' + orphanClaims + ' of ' + totalClaims + ' claims (' +
                    orphanPct.toFixed(2) + '%) have no policy as of ' + valDate +
                    '. Threshold is ' + ORPHAN_THRESHOLD_PCT + '%.');
  }

  // ---------------------------------------------------------------------------
  // 5. Apply to the target in one transaction
  // ---------------------------------------------------------------------------
  exec("BEGIN");
  inTxn = true;

  // 5a. Remove groups that no longer exist for this month (only matters on RERUN)
  var deleted = scalar(
    "DELETE FROM PROCESSING.PRC_CLAIM_SUMMARY t " +
    "WHERE t.VALUATION_DATE = TO_DATE(?) " +
    "  AND NOT EXISTS ( " +
    "    SELECT 1 FROM TMP_CLAIM_ENRICHED e " +
    "    WHERE e.ORPHAN_IND   = 'N' " +
    "      AND e.PRODUCT_CODE = t.PRODUCT_CODE " +
    "      AND e.STATE_CODE   = t.STATE_CODE " +
    "      AND e.CLAIM_TYPE   = t.CLAIM_TYPE " +
    "      AND e.AGING_BUCKET = t.AGING_BUCKET)",
    [valDate]
  );

  // 5b. Upsert; matched rows are only touched when a measure actually changed
  var merge = exec(
    "MERGE INTO PROCESSING.PRC_CLAIM_SUMMARY t " +
    "USING ( " +
    "  SELECT TO_DATE(?) AS VALUATION_DATE, PRODUCT_CODE, STATE_CODE, CLAIM_TYPE, AGING_BUCKET, " +
    "         COUNT(*)                                       AS CLAIM_COUNT, " +
    "         COUNT_IF(CLAIM_STATUS IN " + OPEN_STATUSES + ") AS OPEN_CLAIM_COUNT, " +
    "         SUM(CLAIM_AMOUNT)                              AS INCURRED_AMOUNT, " +
    "         SUM(COALESCE(PAID_AMOUNT, 0))                  AS PAID_AMOUNT, " +
    "         SUM(OUTSTANDING_AMOUNT)                        AS OUTSTANDING_AMOUNT, " +
    "         ROUND(DIV0(COUNT_IF(CLAIM_STATUS = 'DENIED'), COUNT(*)), 4) AS DENIAL_RATE " +
    "  FROM TMP_CLAIM_ENRICHED " +
    "  WHERE ORPHAN_IND = 'N' " +
    "  GROUP BY PRODUCT_CODE, STATE_CODE, CLAIM_TYPE, AGING_BUCKET " +
    ") s " +
    "ON  t.VALUATION_DATE = s.VALUATION_DATE " +
    "AND t.PRODUCT_CODE   = s.PRODUCT_CODE " +
    "AND t.STATE_CODE     = s.STATE_CODE " +
    "AND t.CLAIM_TYPE     = s.CLAIM_TYPE " +
    "AND t.AGING_BUCKET   = s.AGING_BUCKET " +
    "WHEN MATCHED AND HASH(t.CLAIM_COUNT, t.OPEN_CLAIM_COUNT, t.INCURRED_AMOUNT, t.PAID_AMOUNT, " +
    "                      t.OUTSTANDING_AMOUNT, t.DENIAL_RATE) " +
    "              <> HASH(s.CLAIM_COUNT, s.OPEN_CLAIM_COUNT, s.INCURRED_AMOUNT, s.PAID_AMOUNT, " +
    "                      s.OUTSTANDING_AMOUNT, s.DENIAL_RATE) THEN UPDATE SET " +
    "  CLAIM_COUNT        = s.CLAIM_COUNT, " +
    "  OPEN_CLAIM_COUNT   = s.OPEN_CLAIM_COUNT, " +
    "  INCURRED_AMOUNT    = s.INCURRED_AMOUNT, " +
    "  PAID_AMOUNT        = s.PAID_AMOUNT, " +
    "  OUTSTANDING_AMOUNT = s.OUTSTANDING_AMOUNT, " +
    "  DENIAL_RATE        = s.DENIAL_RATE, " +
    "  LAST_UPDATE_USER   = CURRENT_USER(), " +
    "  LAST_UPDATE_DATE   = CURRENT_TIMESTAMP() " +
    "WHEN NOT MATCHED THEN INSERT ( " +
    "  VALUATION_DATE, PRODUCT_CODE, STATE_CODE, CLAIM_TYPE, AGING_BUCKET, " +
    "  CLAIM_COUNT, OPEN_CLAIM_COUNT, INCURRED_AMOUNT, PAID_AMOUNT, OUTSTANDING_AMOUNT, DENIAL_RATE, " +
    "  LAST_UPDATE_USER, LAST_UPDATE_DATE) " +
    "VALUES ( " +
    "  s.VALUATION_DATE, s.PRODUCT_CODE, s.STATE_CODE, s.CLAIM_TYPE, s.AGING_BUCKET, " +
    "  s.CLAIM_COUNT, s.OPEN_CLAIM_COUNT, s.INCURRED_AMOUNT, s.PAID_AMOUNT, s.OUTSTANDING_AMOUNT, s.DENIAL_RATE, " +
    "  CURRENT_USER(), CURRENT_TIMESTAMP())",
    [valDate]
  );
  merge.next();
  var inserted = merge.getColumnValue(1);
  var updated  = merge.getColumnValue(2);

  var counts = 'inserted=' + inserted + ' updated=' + updated + ' deleted=' + deleted +
               ' claims=' + totalClaims + ' orphans=' + orphanClaims;

  // ---------------------------------------------------------------------------
  // 6. DRY_RUN reports what would change, then discards it
  // ---------------------------------------------------------------------------
  if (runMode === 'DRY_RUN') {
    exec("ROLLBACK");
    inTxn = false;
    var dryMsg = 'DRY_RUN ' + valDate + ': ' + counts;
    audit('DRY_RUN', 0, dryMsg);
    return dryMsg;
  }

  exec("COMMIT");
  inTxn = false;

  var msg = 'SUCCESS ' + valDate + ' (' + runMode + '): ' + counts;
  audit('SUCCESS', inserted + updated, msg);
  return msg;

} catch (err) {
  if (inTxn) {
    exec("ROLLBACK");
  }
  audit('FAILED', 0, err.message);
  throw err;
}
$$;

-- =============================================================================
-- SECTION 6: POLICY procedures
-- SP_LOAD_STG_POLICY is implemented from the DATA-214 task template.
-- SP_LOAD_PRC_POLICY is rewritten: the repo version concatenates an unquoted
-- date into SQL, inserts SELECT * (24 cols into a 19-col table), skips the
-- CURRENT_IND filter, and has no transaction or audit row.
-- =============================================================================

CREATE OR REPLACE PROCEDURE ETL.SP_LOAD_STG_POLICY()
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
/*******************************************************************************
 * Procedure : ETL.SP_LOAD_STG_POLICY
 * Purpose   : Reload STAGING.STG_POLICY from the policy files on the stage
 * Params    : none
 * Reads     : @STAGING.POLICY_STAGE (files matching policy_YYYYMMDD.csv)
 * Writes    : STAGING.STG_POLICY, ETL.LOAD_AUDIT
 * Run order : step 1 of the POLICY JS7 job
 * Change log: 2026-10-13  DATA-214  Initial version
 ******************************************************************************/

var PROC_NAME = 'ETL.SP_LOAD_STG_POLICY';
var TARGET    = 'STAGING.STG_POLICY';

function exec(sql, binds) {
  return snowflake.createStatement({ sqlText: sql, binds: binds || [] }).execute();
}

function scalar(sql, binds) {
  var rs = exec(sql, binds);
  rs.next();
  return rs.getColumnValue(1);
}

function audit(status, rows, msg) {
  exec(
    "INSERT INTO ETL.LOAD_AUDIT (PROC_NAME, TARGET_TABLE, STATUS, ROW_COUNT, MESSAGE, RUN_USER, RUN_TS) " +
    "SELECT ?, ?, ?, ?, ?, CURRENT_USER(), CURRENT_TIMESTAMP()",
    [PROC_NAME, TARGET, status, rows, msg]
  );
}

try {
  exec("BEGIN");

  exec("DELETE FROM STAGING.STG_POLICY");

  exec(
    "COPY INTO STAGING.STG_POLICY " +
    "FROM @STAGING.POLICY_STAGE " +
    "FILE_FORMAT = (FORMAT_NAME = 'STAGING.FF_CSV_STD') " +
    "PATTERN = '.*policy_[0-9]{8}[.]csv' " +
    "ON_ERROR = 'ABORT_STATEMENT'"
  );

  // Premium may be zero for paid-up policies but never negative
  var negative = scalar("SELECT COUNT(*) FROM STAGING.STG_POLICY WHERE ANNUAL_PREMIUM < ?", [0]);
  if (negative > 0) {
    throw new Error('Negative ANNUAL_PREMIUM rows: ' + negative);
  }

  var loaded = scalar("SELECT COUNT(*) FROM STAGING.STG_POLICY");

  exec("COMMIT");

  var msg = 'SUCCESS: loaded=' + loaded;
  audit('SUCCESS', loaded, msg);
  return msg;

} catch (err) {
  exec("ROLLBACK");
  audit('FAILED', 0, err.message);
  throw err;
}
$$;

CREATE OR REPLACE PROCEDURE ETL.SP_LOAD_HIST_POLICY(P_LOAD_DATE VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
var PROC_NAME = 'ETL.SP_LOAD_HIST_POLICY';
var TARGET    = 'HISTORY.HIST_POLICY';

function exec(sql, binds) {
  return snowflake.createStatement({ sqlText: sql, binds: binds || [] }).execute();
}

function rowsAffected(rs) {
  rs.next();
  return rs.getColumnValue(1);
}

function audit(status, rows, msg) {
  exec(
    "INSERT INTO ETL.LOAD_AUDIT (PROC_NAME, TARGET_TABLE, STATUS, ROW_COUNT, MESSAGE, RUN_USER, RUN_TS) " +
    "SELECT ?, ?, ?, ?, ?, CURRENT_USER(), CURRENT_TIMESTAMP()",
    [PROC_NAME, TARGET, status, rows, msg]
  );
}

try {
  exec("BEGIN");

  var closed = rowsAffected(exec(
    "UPDATE HISTORY.HIST_POLICY h " +
    "SET END_EFFECTIVE_DATE = DATEADD(DAY, -1, TO_DATE(?, 'YYYY-MM-DD')), " +
    "    CURRENT_IND        = 'N', " +
    "    LAST_UPDATE_USER   = CURRENT_USER(), " +
    "    LAST_UPDATE_DATE   = CURRENT_TIMESTAMP() " +
    "FROM STAGING.STG_POLICY s " +
    "WHERE h.POLICY_ID = s.POLICY_ID " +
    "  AND h.CURRENT_IND = 'Y' " +
    "  AND HASH(h.POLICY_NUMBER, h.PRODUCT_CODE, h.POLICY_STATUS, h.ISSUE_DATE, h.EFFECTIVE_DATE, " +
    "           h.TERMINATION_DATE, h.ANNUAL_PREMIUM, h.PAYMENT_FREQUENCY, h.INSURED_FIRST_NAME, " +
    "           h.INSURED_LAST_NAME, h.INSURED_DOB, h.INSURED_SSN, h.STATE_CODE, h.AGENT_ID) " +
    "   <> HASH(s.POLICY_NUMBER, s.PRODUCT_CODE, s.POLICY_STATUS, s.ISSUE_DATE, s.EFFECTIVE_DATE, " +
    "           s.TERMINATION_DATE, s.ANNUAL_PREMIUM, s.PAYMENT_FREQUENCY, s.INSURED_FIRST_NAME, " +
    "           s.INSURED_LAST_NAME, s.INSURED_DOB, s.INSURED_SSN, s.STATE_CODE, s.AGENT_ID)",
    [P_LOAD_DATE]
  ));

  var inserted = rowsAffected(exec(
    "INSERT INTO HISTORY.HIST_POLICY (" +
    "  POLICY_ID, POLICY_NUMBER, PRODUCT_CODE, POLICY_STATUS, ISSUE_DATE, EFFECTIVE_DATE, " +
    "  TERMINATION_DATE, ANNUAL_PREMIUM, PAYMENT_FREQUENCY, INSURED_FIRST_NAME, INSURED_LAST_NAME, " +
    "  INSURED_DOB, INSURED_SSN, STATE_CODE, AGENT_ID, SOURCE_FILE_DATE, " +
    "  BEGIN_EFFECTIVE_DATE, END_EFFECTIVE_DATE, CURRENT_IND, LAST_UPDATE_USER, LAST_UPDATE_DATE) " +
    "SELECT s.POLICY_ID, s.POLICY_NUMBER, s.PRODUCT_CODE, s.POLICY_STATUS, s.ISSUE_DATE, s.EFFECTIVE_DATE, " +
    "       s.TERMINATION_DATE, s.ANNUAL_PREMIUM, s.PAYMENT_FREQUENCY, s.INSURED_FIRST_NAME, s.INSURED_LAST_NAME, " +
    "       s.INSURED_DOB, s.INSURED_SSN, s.STATE_CODE, s.AGENT_ID, s.SOURCE_FILE_DATE, " +
    "       TO_DATE(?, 'YYYY-MM-DD'), TO_DATE('9999-12-31'), 'Y', CURRENT_USER(), CURRENT_TIMESTAMP() " +
    "FROM STAGING.STG_POLICY s " +
    "LEFT JOIN HISTORY.HIST_POLICY h " +
    "  ON h.POLICY_ID = s.POLICY_ID AND h.CURRENT_IND = 'Y' " +
    "WHERE h.POLICY_ID IS NULL",
    [P_LOAD_DATE]
  ));

  exec("COMMIT");

  var msg = 'SUCCESS: inserted=' + inserted + ' closed=' + closed;
  audit('SUCCESS', inserted, msg);
  return msg;

} catch (err) {
  exec("ROLLBACK");
  audit('FAILED', 0, err.message);
  throw err;
}
$$;

CREATE OR REPLACE PROCEDURE ETL.SP_LOAD_PRC_POLICY(P_VALUATION_DATE VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
/*******************************************************************************
 * Procedure : ETL.SP_LOAD_PRC_POLICY
 * Purpose   : Reload PRC_POLICY with the current version of each policy
 * Params    : P_VALUATION_DATE - any date in the reporting month, 'YYYY-MM-DD';
 *             stored as the last day of that month
 * Reads     : HISTORY.HIST_POLICY
 * Writes    : PROCESSING.PRC_POLICY, ETL.LOAD_AUDIT
 * Run order : step 3 of the POLICY JS7 job
 * Change log: 2026-10-02  DATA-215  Initial version
 *             2026-10-13  DATA-215  Binds, explicit columns, current rows only, audit
 ******************************************************************************/

var PROC_NAME = 'ETL.SP_LOAD_PRC_POLICY';
var TARGET    = 'PROCESSING.PRC_POLICY';

function exec(sql, binds) {
  return snowflake.createStatement({ sqlText: sql, binds: binds || [] }).execute();
}

function rowsAffected(rs) {
  rs.next();
  return rs.getColumnValue(1);
}

function audit(status, rows, msg) {
  exec(
    "INSERT INTO ETL.LOAD_AUDIT (PROC_NAME, TARGET_TABLE, STATUS, ROW_COUNT, MESSAGE, RUN_USER, RUN_TS) " +
    "SELECT ?, ?, ?, ?, ?, CURRENT_USER(), CURRENT_TIMESTAMP()",
    [PROC_NAME, TARGET, status, rows, msg]
  );
}

try {
  exec("BEGIN");

  exec("DELETE FROM PROCESSING.PRC_POLICY");

  var inserted = rowsAffected(exec(
    "INSERT INTO PROCESSING.PRC_POLICY (" +
    "  POLICY_ID, POLICY_NUMBER, PRODUCT_CODE, POLICY_STATUS, ISSUE_DATE, EFFECTIVE_DATE, " +
    "  TERMINATION_DATE, ANNUAL_PREMIUM, PAYMENT_FREQUENCY, INSURED_FIRST_NAME, INSURED_LAST_NAME, " +
    "  INSURED_DOB, INSURED_SSN, STATE_CODE, AGENT_ID, SOURCE_FILE_DATE, " +
    "  VALUATION_DATE, LAST_UPDATE_USER, LAST_UPDATE_DATE) " +
    "SELECT POLICY_ID, POLICY_NUMBER, PRODUCT_CODE, POLICY_STATUS, ISSUE_DATE, EFFECTIVE_DATE, " +
    "       TERMINATION_DATE, ANNUAL_PREMIUM, PAYMENT_FREQUENCY, INSURED_FIRST_NAME, INSURED_LAST_NAME, " +
    "       INSURED_DOB, INSURED_SSN, STATE_CODE, AGENT_ID, SOURCE_FILE_DATE, " +
    "       LAST_DAY(TO_DATE(?, 'YYYY-MM-DD')), CURRENT_USER(), CURRENT_TIMESTAMP() " +
    "FROM HISTORY.HIST_POLICY " +
    "WHERE CURRENT_IND = 'Y'",
    [P_VALUATION_DATE]
  ));

  exec("COMMIT");

  var msg = 'SUCCESS: inserted=' + inserted;
  audit('SUCCESS', inserted, msg);
  return msg;

} catch (err) {
  exec("ROLLBACK");
  audit('FAILED', 0, err.message);
  throw err;
}
$$;

-- =============================================================================
-- SECTION 7: Verify deployment
-- =============================================================================

SHOW TABLES IN DATABASE DEMO_DB;
SHOW PROCEDURES IN SCHEMA DEMO_DB.ETL;

-- =============================================================================
-- SECTION 8 (optional): Load sample data and run the month-end pipeline.
-- PUT only works from SnowSQL / a driver, not Snowsight. In Snowsight, upload
-- data/sample/policy_20260930.csv to @STAGING.POLICY_STAGE via the UI instead.
-- =============================================================================

-- PUT file://data/sample/policy_20260930.csv @STAGING.POLICY_STAGE AUTO_COMPRESS = FALSE OVERWRITE = TRUE;

-- POLICY job
-- CALL ETL.SP_LOAD_STG_POLICY();
-- CALL ETL.SP_LOAD_HIST_POLICY('2026-09-30');
-- CALL ETL.SP_LOAD_PRC_POLICY('2026-09-30');

-- CLAIM job (requires a claim_YYYYMMDD.csv on @STAGING.CLAIM_STAGE)
-- CALL ETL.SP_LOAD_STG_CLAIM();
-- CALL ETL.SP_LOAD_HIST_CLAIM('2026-09-30');
-- CALL ETL.SP_LOAD_PRC_CLAIM('2026-09-30');
-- CALL ETL.SP_LOAD_PRC_CLAIM_SUMMARY('2026-09-30', 'NORMAL');

-- SELECT * FROM ETL.LOAD_AUDIT ORDER BY RUN_TS DESC LIMIT 20;
