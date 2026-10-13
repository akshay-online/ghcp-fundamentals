-- Validation queries for HISTORY.HIST_CLAIM
-- Each query returns ZERO rows when the data is correct.
-- Run after ETL.SP_LOAD_HIST_CLAIM. Set the load date first:
SET LOAD_DATE = '2026-09-30';

-- T1: exactly one current row per CLAIM_ID
SELECT CLAIM_ID, COUNT(*) AS CURRENT_ROWS
FROM HISTORY.HIST_CLAIM
WHERE CURRENT_IND = 'Y'
GROUP BY CLAIM_ID
HAVING COUNT(*) <> 1;

-- T2: current rows are open-ended; closed rows are not
SELECT CLAIM_ID, CURRENT_IND, END_EFFECTIVE_DATE
FROM HISTORY.HIST_CLAIM
WHERE (CURRENT_IND = 'Y' AND END_EFFECTIVE_DATE <> '9999-12-31')
   OR (CURRENT_IND = 'N' AND END_EFFECTIVE_DATE  = '9999-12-31');

-- T3: every staging row has a current history row
SELECT s.CLAIM_ID
FROM STAGING.STG_CLAIM s
LEFT JOIN HISTORY.HIST_CLAIM h
  ON h.CLAIM_ID = s.CLAIM_ID AND h.CURRENT_IND = 'Y'
WHERE h.CLAIM_ID IS NULL;
