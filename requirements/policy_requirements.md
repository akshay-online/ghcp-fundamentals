# Policy Master Data – Monthly Load

**From:** Policy Administration (business owner: Policy Ops)
**Date received:** 2026-09-22
**Related spec:** `specs/policy_column_spec.csv`

## Background

Actuarial and Finance reporting need a reliable monthly view of all in-force and
recently terminated individual policies. Today they receive a spreadsheet by email
each month and reconcile it by hand. We want this data in Snowflake, loaded the
same way as the Claims data, so reports can join policies to claims.

## What we will send

- One CSV file per month, named `policy_YYYYMMDD.csv`, where the date is the
  last business day of the month the extract was taken.
- The file contains every policy that was active at any point in the last
  24 months.
- Header row included. Comma delimited. Text fields may be wrapped in double quotes.
- Dates are sent as `YYYY-MM-DD`.

## What we need

1. Keep a full history of how each policy changed over time (status, premium,
   agent, etc.) so Finance can see what a policy looked like at any month end.
2. A table with the latest view of each policy for the month being reported.
   Reports will filter on the month.
3. Customer personal details are sensitive and must be protected.
4. Premium must be stored to 2 decimal places.
5. Loads should run after the monthly file arrives, as part of the existing
   month-end JS7 schedule, after the Claims load.

## Business rules

- A policy can change status many times (e.g. ACTIVE → LAPSED → REINSTATED).
- Policies are never physically deleted from the source. A terminated policy will
  appear with status TERMINATED and a termination date, and will drop out of the
  file 24 months after termination.
- `ANNUAL_PREMIUM` can be zero for paid-up policies but should never be negative.
- `STATE_CODE` is the 2-letter US state where the policy was issued.

## Out of scope

- Group policies (separate feed, later phase).
- Agent hierarchy and commissions.

## Contacts

- Business questions: Policy Ops lead
- File delivery: Policy Admin IT
