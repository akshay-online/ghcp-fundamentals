-- HISTORY.HIST_CLAIM
-- Every version of every claim (SCD Type 2).
-- Source spec: specs/claim_column_spec.csv + 5 tracking columns (docs/snowflake_standards.md)

CREATE TABLE IF NOT EXISTS HISTORY.HIST_CLAIM (
  CLAIM_ID              VARCHAR(20)   NOT NULL COMMENT 'Unique claim identifier',
  POLICY_ID             VARCHAR(20)   NOT NULL COMMENT 'Policy the claim was made against',
  CLAIM_TYPE            VARCHAR(20)   NOT NULL COMMENT 'ACCIDENT, ILLNESS, HOSPITAL, CANCER',
  CLAIM_STATUS          VARCHAR(15)   NOT NULL COMMENT 'OPEN, IN_REVIEW, PAID, DENIED, CLOSED',
  LOSS_DATE             DATE          NOT NULL COMMENT 'Date the loss event happened',
  REPORTED_DATE         DATE          NOT NULL COMMENT 'Date the claim was reported',
  CLAIM_AMOUNT          NUMBER(18,2)  NOT NULL COMMENT 'Amount claimed in USD',
  PAID_AMOUNT           NUMBER(18,2)           COMMENT 'Amount paid in USD; empty until paid',
  CLAIMANT_NAME         VARCHAR(100)  NOT NULL COMMENT 'Full name of the claimant',
  DIAGNOSIS_CODE        VARCHAR(10)            COMMENT 'ICD-10 diagnosis code',
  SOURCE_FILE_DATE      DATE          NOT NULL COMMENT 'Extract date taken from the file name',
  BEGIN_EFFECTIVE_DATE  DATE          NOT NULL COMMENT 'Load date this version became valid',
  END_EFFECTIVE_DATE    DATE          NOT NULL COMMENT '9999-12-31 while current; load date - 1 when closed',
  CURRENT_IND           CHAR(1)       NOT NULL COMMENT 'Y = current version, N = closed',
  LAST_UPDATE_USER      VARCHAR(100)  NOT NULL COMMENT 'User that last wrote the row',
  LAST_UPDATE_DATE      TIMESTAMP_NTZ NOT NULL COMMENT 'When the row was last written'
)
COMMENT = 'History: all versions of each claim, SCD Type 2 on CLAIM_ID';
