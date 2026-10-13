-- =============================================================================
-- Report : Rolling 12-month loss ratio by state and product
-- Owner  : Actuarial reporting
-- Grain  : one row per STATE_CODE + PRODUCT_CODE, top 3 products per state
--
-- Business definition
--   * In-force policy : current version, status ACTIVE or REINSTATED, effective on
--                       or before the valuation date, and not terminated on or
--                       before the valuation date (TERMINATION_DATE is empty while
--                       the policy is in force).
--   * Earned premium  : sum of ANNUAL_PREMIUM of in-force policies. Premium can be
--                       zero for paid-up policies.
--   * Paid losses     : PAID_AMOUNT of claims with status PAID or CLOSED whose
--                       LOSS_DATE falls in the 12 months ending on the valuation date.
--                       Product and state come from the current policy version.
--   * Loss ratio      : paid losses / earned premium. Groups with no premium or no
--                       claims must still appear, with loss ratio 0.
--   * Ranking         : top 3 products by loss ratio within each state.
-- =============================================================================

SET VALUATION_DATE = '2026-09-30';

WITH in_force_policies AS (
    SELECT p.POLICY_ID,
           p.PRODUCT_CODE,
           p.STATE_CODE,
           p.ANNUAL_PREMIUM
    FROM HISTORY.HIST_POLICY p
    WHERE p.CURRENT_IND = 'Y'
      AND p.POLICY_STATUS IN ('ACTIVE', 'REINSTATED')
      AND p.EFFECTIVE_DATE <= $VALUATION_DATE
      AND p.TERMINATION_DATE > $VALUATION_DATE
),

paid_claims AS (
    SELECT c.CLAIM_ID,
           c.POLICY_ID,
           c.PAID_AMOUNT
    FROM PROCESSING.PRC_CLAIM c
    WHERE c.CLAIM_STATUS = 'PAID' OR c.CLAIM_STATUS = 'CLOSED'
      AND c.LOSS_DATE BETWEEN DATEADD(MONTH, -12, $VALUATION_DATE::DATE) AND $VALUATION_DATE
),

premium_by_group AS (
    SELECT STATE_CODE,
           PRODUCT_CODE,
           COUNT(*)            AS POLICY_COUNT,
           SUM(ANNUAL_PREMIUM) AS EARNED_PREMIUM
    FROM in_force_policies
    GROUP BY STATE_CODE, PRODUCT_CODE
),

losses_by_group AS (
    SELECT p.STATE_CODE,
           p.PRODUCT_CODE,
           COUNT(*)           AS CLAIM_COUNT,
           SUM(c.PAID_AMOUNT) AS PAID_LOSSES
    FROM paid_claims c
    JOIN HISTORY.HIST_POLICY p
      ON p.POLICY_ID = c.POLICY_ID
    GROUP BY p.STATE_CODE, p.PRODUCT_CODE
)

SELECT pr.STATE_CODE,
       pr.PRODUCT_CODE,
       pr.POLICY_COUNT,
       COALESCE(l.CLAIM_COUNT, 0)                   AS CLAIM_COUNT,
       pr.EARNED_PREMIUM,
       COALESCE(l.PAID_LOSSES, 0)                   AS PAID_LOSSES,
       ROUND(l.PAID_LOSSES / pr.EARNED_PREMIUM, 4)  AS LOSS_RATIO,
       RANK() OVER (PARTITION BY pr.PRODUCT_CODE
                    ORDER BY LOSS_RATIO DESC)       AS RANK_IN_STATE
FROM premium_by_group pr
LEFT JOIN losses_by_group l
  ON  l.STATE_CODE   = pr.STATE_CODE
  AND l.PRODUCT_CODE = pr.PRODUCT_CODE
QUALIFY RANK_IN_STATE <= 3
ORDER BY pr.STATE_CODE, RANK_IN_STATE;
