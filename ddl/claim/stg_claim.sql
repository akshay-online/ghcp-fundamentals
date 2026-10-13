-- STAGING.STG_CLAIM
-- Raw landing of the monthly claims file. Business columns only.
-- Source spec: specs/claim_column_spec.csv

CREATE TABLE IF NOT EXISTS STAGING.STG_CLAIM (
  CLAIM_ID          VARCHAR(20)   NOT NULL COMMENT 'Unique claim identifier',
  POLICY_ID         VARCHAR(20)   NOT NULL COMMENT 'Policy the claim was made against',
  CLAIM_TYPE        VARCHAR(20)   NOT NULL COMMENT 'ACCIDENT, ILLNESS, HOSPITAL, CANCER',
  CLAIM_STATUS      VARCHAR(15)   NOT NULL COMMENT 'OPEN, IN_REVIEW, PAID, DENIED, CLOSED',
  LOSS_DATE         DATE          NOT NULL COMMENT 'Date the loss event happened',
  REPORTED_DATE     DATE          NOT NULL COMMENT 'Date the claim was reported',
  CLAIM_AMOUNT      NUMBER(18,2)  NOT NULL COMMENT 'Amount claimed in USD',
  PAID_AMOUNT       NUMBER(18,2)           COMMENT 'Amount paid in USD; empty until paid',
  CLAIMANT_NAME     VARCHAR(100)  NOT NULL COMMENT 'Full name of the claimant',
  DIAGNOSIS_CODE    VARCHAR(10)            COMMENT 'ICD-10 diagnosis code',
  SOURCE_FILE_DATE  DATE          NOT NULL COMMENT 'Extract date taken from the file name'
)
COMMENT = 'Staging: monthly claims file, truncated and reloaded each run';
