# KPI fiscal month selection

Overview defaults to the complete September–August fiscal year in Europe/Stockholm.
The URL stores fiscal_year as the September start year and months as calendar month
numbers ordered September–August. Disjoint selections stay disjoint.

YTD means complete selected months from September through the current month;
historical fiscal years use all twelve months and future-year YTD is disabled.
This is a month filter, not a day-based elapsed-period comparison.

Hub entry point: hub_kpi_overview_months_v1(tenant, fiscal_year, selected_months,
cost_center, filters). It returns current/previous metrics, monthly values,
categories, business groups, economic units, vehicles, time and derived KPI.
hub_kpi_analysis_months_v1 uses the same classified facts and month predicate for
drilldown and exports. Source facts and dated identity/classification rules remain
owned by the existing Hub. Fiscal-year facts are filtered after calculation to
preserve the existing weekly personnel calculation when changing month selection.

The private snapshot needs protected TransPA views and validates auth.uid plus
kpi.read before reading any tenant data. It is not exposed through the public
Data API. Public RPCs retain invoker security and anonymous execution is revoked.
No source, canonical identity, sync-engine or data-quality mutations are included.

Verification on real Elleholms data:
- FY 2025/2026 Sep + Oct + Jan: revenue 19,227,571.09; costs 10,849,867.03;
  result 8,377,704.06. Exactly three monthly points reconcile with totals.
- FY 2026/2027 Sep + Oct + Jan, KST 30: cost 1,140,414.58 and 4,061.55
  vehicle hours at verification time. Financial drilldown reconciles with cards.
- Previous year uses identical month numbers; cross-tenant requests and empty
  selections are rejected; anon has no execute permission.
- npm run build and targeted ESLint pass.

Weekly revenue display is replaced by the primary monthly chart. Exact date
intervals remain available in the KPI view without a month selection.
Monthly points retain the selected months and all active filters while adding
the clicked month as date_from/date_to for analysis.

The report reuses selected classified facts for the unclassified summary. These
two bounded report RPCs have a PostgREST-hoisted 30-second execution limit; global
and role timeouts remain unchanged.
