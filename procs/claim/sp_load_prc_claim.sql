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
