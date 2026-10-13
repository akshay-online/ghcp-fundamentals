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
