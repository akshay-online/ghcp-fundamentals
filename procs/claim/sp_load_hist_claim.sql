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
