# DATA-214 – Load POLICY history table (SCD Type 2)

As a Finance analyst, I want every change to a policy kept in HISTORY.HIST_POLICY,
so that I can see what any policy looked like at a past month end.

The monthly policy file lands in STAGING.STG_POLICY. 
A procedure must compare it to the current rows in HISTORY.HIST_POLICY on POLICY_ID, close rows that changed, and insert new versions and new policies. It should follow the same pattern as the
CLAIM history load.