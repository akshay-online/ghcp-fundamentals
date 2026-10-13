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
