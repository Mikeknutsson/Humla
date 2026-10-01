# Financial reconciliation follow-up

The Overview and KPI views use the same fiscal-month Hub report for complete
month selections and default fiscal years. Bookmarked complete-month date URLs
are translated to the same fiscal year/month selection instead of resetting the
Overview to the current year.

Dated Workify article rules classify revenue to their explicit cost center.
The project/vehicle registry is the fallback when no dated article rule declares
one. Existing vehicle identities, group matching and source transactions remain
unchanged. The shared classified-facts function makes this consistent across
cards, analysis and exports.

Vehicle rows now include Ej fördelat and link to its original transactions.
The Hub reconciles monthly values and vehicle totals against the same facts;
vehicle money rounding may differ by cents when adding individually rounded rows.
The footer uses the authoritative Hub totals. A comparison is shown only when
both years have revenue and NEXT facts in every selected month. This tests data
presence, not completeness against an external bookkeeping system. Explicit
analysis dates are shifted by one year for prior-year queries.

The UI separates NEXT cost rows, added TransPA wage estimates and registered
depreciation. It identifies pending imports and avoids claiming 100% overall
financial data coverage merely because the calculation's included facts are valid.
Revenue is currently Workify article amounts by Artikeldatum, across all order
statuses with valid amounts; it is not restricted to invoiced orders.

Verification: real-data fiscal-year and disjoint-month requests reconcile
against analysis, category costs and monthly series. Vehicle reconciliation
allows per-row cent rounding. Period regression tests, targeted ESLint and
npm run build pass.

An external report's aggregate is insufficient to resolve a difference in
transaction inclusion. A monthly/transaction export with period and report
filters is needed for external reconciliation. Identical source rows are
candidates for review, not grounds to delete legitimate repeated article lines.
Pending parallel Hub ingestion remains untouched.
