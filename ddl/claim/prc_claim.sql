-- PROCESSING.PRC_CLAIM
-- Current version of each claim for the valuation month. Queried by reports.
-- Sensitive columns are masked by policy (see ddl/claim/masking_claim.sql).

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
