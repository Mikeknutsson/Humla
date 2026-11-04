# Driver goal coaching

The chauffeur view prioritizes vehicle goal progress. Zero on the gauge means the dated weighted result target is met. Hub computes relative deviation: (result - target result) / positive target result * 100. An 8% margin against a 10% goal therefore reads 20% below goal; the configured margin itself is not displayed. The needle is clamped at -50/+50; exact out-of-range deviation remains visible and accessible.

Previous equal-duration dates and the same dates one year earlier are aggregated against their own dated targets. Missing revenue, target, or comparison remains unknown. Change is expressed in percentage points of relative goal deviation. Compare workload and calendar differences before interpreting short periods.

The source remains canonical Person -> TransPA annotation -> canonical Vehicle -> published EconomicUnit. It describes whole vehicle context, not personal driver performance. Existing self/owner authorization and percentage-only economic fields are retained. No accounts, permissions or financial facts are changed.

Below-goal vehicles may receive an approximate fuel-saving scenario based on matched positive Piusi fuel costs and liters. It covers at most 10% of the period's tanked liters and at most 100% of the goal gap. All current fuel prices are provisional; the UI calls this an estimate at the same workload and distinguishes tanking from measured consumption. Counts of extra loads/emptyings are intentionally not invented without incremental revenue and cost evidence; instead the driver gets a planning action with dispatch. Options are alternatives, not cumulative promised savings or demands for additional work.

Validation: goal arithmetic including 8/10, zero/unknown targets, actual scoped vehicle results, both comparison periods, private helper grants, legacy self/owner/cross-tenant regression checks, TypeScript, production build and component rendering.
