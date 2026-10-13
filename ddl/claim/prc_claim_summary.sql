-- PROCESSING.PRC_CLAIM_SUMMARY
-- Month-end claim summary by product, state, claim type and aging bucket.
-- Loaded by ETL.SP_LOAD_PRC_CLAIM_SUMMARY. Grain: VALUATION_DATE + 4 dimension columns.

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
