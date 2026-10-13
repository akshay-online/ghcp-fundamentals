CREATE OR REPLACE PROCEDURE ETL.SP_LOAD_PRC_POLICY(p_valuation_date VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
/*******************************************************************************
 * Procedure : ETL.SP_LOAD_PRC_POLICY
 * Purpose   : Reload PRC_POLICY with policies for the valuation month
 * Params    : p_valuation_date - last day of the reporting month, 'YYYY-MM-DD'
 * Reads     : HISTORY.HIST_POLICY
 * Writes    : PROCESSING.PRC_POLICY
 * Run order : step 3 of the POLICY JS7 job
 * Change log: 2026-10-02  DATA-215  Initial version
 ******************************************************************************/

var vdate = p_valuation_date;

snowflake.execute({ sqlText: "DELETE FROM PROCESSING.PRC_POLICY" });

var sql =
  "INSERT INTO PROCESSING.PRC_POLICY " +
  "SELECT *, " + vdate + ", CURRENT_USER(), CURRENT_TIMESTAMP() " +
  "FROM HISTORY.HIST_POLICY";

snowflake.execute({ sqlText: sql });

return "done";
$$;
