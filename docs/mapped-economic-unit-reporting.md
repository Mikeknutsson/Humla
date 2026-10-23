# Mapped economic units in reports

KPI and monthly report RPCs project their economic-unit lists through the canonical Hub EconomicUnit catalog. Automatically generated vehicle/project entries and imported aliases are not displayed as separate economic units. A mapped unit with only one component remains visible.

This is a presentation projection after aggregation. Financial facts, report metrics, date-versioned allocation, child objects and transaction drilldowns remain unchanged. Unmapped amounts remain in the full-scope totals. The response includes an `unmapped_economic_units` summary for reconciliation. Month, YTD and previous-period sections follow the same rule.

Monthly cache hits are projected on read, without rebuilding the prepared dataset. The application cache version is incremented to invalidate earlier mixed lists. Excel and PDF economic-unit sections consume the same projected report.

Verification: authenticated-role projection retained a canonical unit and its children, removed an automatic vehicle entry, preserved metrics, and reported excluded-list amounts separately. The existing September transport monthly snapshot changed from 44 to 40 displayed entries with identical metrics. TypeScript validation passed.
