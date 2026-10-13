-- =============================================================================
-- TASK      : Build ETL.SP_LOAD_STG_POLICY  (Jira DATA-214, step 1 of POLICY JS7 job)
-- LANGUAGE  : Snowflake SQL + Snowflake Stored Procedure written in JAVASCRIPT
-- STANDARDS : docs/snowflake_standards.md  (follow procs/claim/sp_load_stg_claim.sql)
-- =============================================================================
--
-- REQUIREMENT
--   Policy Admin drops one CSV per month on the stage, named policy_YYYYMMDD.csv
--   (date = last business day of the month). Each run must fully reload the
--   staging table from that file so the HIST step can compare it to history.
--
-- AVAILABLE OBJECTS (database DEMO_DB)
--   Stage        : @STAGING.POLICY_STAGE
--   File format  : STAGING.FF_CSV_STD  (CSV, header skipped, '"' enclosed, YYYY-MM-DD dates)
--   Audit table  : ETL.LOAD_AUDIT (PROC_NAME, TARGET_TABLE, STATUS, ROW_COUNT,
--                                  MESSAGE, RUN_USER, RUN_TS)
--   Target table : STAGING.STG_POLICY  -- business columns only, in this order:
--       POLICY_ID           VARCHAR(20)   NOT NULL  key
--       POLICY_NUMBER       VARCHAR(30)   NOT NULL
--       PRODUCT_CODE        VARCHAR(10)   NOT NULL
--       POLICY_STATUS       VARCHAR(15)   NOT NULL  ACTIVE | LAPSED | REINSTATED | TERMINATED
--       ISSUE_DATE          DATE          NOT NULL
--       EFFECTIVE_DATE      DATE          NOT NULL
--       TERMINATION_DATE    DATE          NULL      empty while in force
--       ANNUAL_PREMIUM      NUMBER(18,2)  NOT NULL  zero allowed, never negative
--       PAYMENT_FREQUENCY   VARCHAR(10)   NOT NULL  MONTHLY | QUARTERLY | ANNUAL
--       INSURED_FIRST_NAME  VARCHAR(50)   NOT NULL  sensitive
--       INSURED_LAST_NAME   VARCHAR(50)   NOT NULL  sensitive
--       INSURED_DOB         DATE          NOT NULL  sensitive
--       INSURED_SSN         VARCHAR(11)   NULL      sensitive, 999-99-9999
--       STATE_CODE          VARCHAR(2)    NOT NULL
--       AGENT_ID            VARCHAR(15)   NULL
--       SOURCE_FILE_DATE    DATE          NOT NULL  extract date from the file name
--
-- RULES
--   1. LANGUAGE JAVASCRIPT, EXECUTE AS CALLER, RETURNS VARCHAR, no arguments.
--   2. Standard header comment block inside the $$ body.
--   3. BEGIN -> DELETE FROM STAGING.STG_POLICY -> COPY INTO from the stage using
--      PATTERN '.*policy_[0-9]{8}[.]csv' and ON_ERROR = 'ABORT_STATEMENT' -> COMMIT.
--   4. After the load, count rows where ANNUAL_PREMIUM < 0. If any exist, throw an
--      error "Negative ANNUAL_PREMIUM rows: <n>" so the load is rolled back.
--   5. Use binds with ? placeholders for every value. No string concatenation of values.
--   6. ROLLBACK in catch, write a FAILED audit row, then re-throw.
--   7. Add debug or info logging as needed to trace the execution steps.
--
-- EXPECTED OUTPUT
--   Success : returns 'SUCCESS: loaded=<n>' and writes one SUCCESS row to ETL.LOAD_AUDIT
--   Failure : STG_POLICY unchanged, one FAILED row in ETL.LOAD_AUDIT, error raised to JS7
-- =============================================================================

-- Step 1: create the procedure ETL.SP_LOAD_STG_POLICY


-- Step 2: call the procedure



-- Step 3: query ETL.LOAD_AUDIT for the latest 5 runs of ETL.SP_LOAD_STG_POLICY

