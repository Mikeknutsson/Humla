# Sågning allocation

Confirmed by Mike on 2026-10-22, effective for available history from 2025-09-01.

Hub owns the persistent rule, canonical EconomicUnit and calculations. Article 12-04 is split into retained truck revenue (signed billed hours × SEK 1,250) and residual saw revenue. The residual can be negative. Source amounts and identities remain in `_humla_saw_activity`; original imports are untouched. Derived saw revenue has zero quantity to prevent a second billed-hours count. The billable-hours snapshot continues to belong to the truck.

NEXT project identities 10648 and 11291 resolve to canonical Hub objects. Their costs move to Sågning, including amounts previously distributed between trucks. Invoice lines from the exact named supplier Ett strå vassare i Sölvesborg AB are split 50/50, taking precedence over project matching. The retained half stays on its former unit/cost center. Signed credits follow the same rules. All invoice values use published net amounts.

Project 10818 is shared. Only explicit activity evidence in the available description fields qualifies for automatic allocation; unmatched rows remain on their original unit and are shown for review. The current imported texts do not establish which of these rows concern sawing. The reported result is therefore before unverified costs, not a final job margin.

The generation publication hook runs after existing allocations and identity resolution. It asserts unchanged fiscal-year revenue/cost totals and is idempotent. Derived display facts and full facts are updated together. Anonymous RPC access is denied and all detail rows pass the existing dated assignment authorization. Limited personal/unit selections do not show a full business result.

Validation: `supabase/tests/saw_activity_allocation.sql` (rollback) verifies financial preservation, idempotence, hourly revenue, supplier share, removal of project costs from trucks, display agreement, order/cost reconciliation and anonymous denial. TypeScript and scoped lint passed. Full-year 25/26 verification: gross 1,708,850; hours 1,032.5; truck 1,290,625; saw 418,225; saw cost 613,009.62; provisional result -194,784.62. Published source data can change these amounts after refresh.
