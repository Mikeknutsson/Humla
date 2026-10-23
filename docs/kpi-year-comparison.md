# Same-period comparison

Overview and KPI share a separate comparison panel. The selected fiscal months and supported scope filters are applied independently to the selected year and the previous fiscal year. Absolute day filters shift one year, including leap-day handling.

Hub calculates differences, relative changes and percentage-point changes. Economic units match by the canonical key returned by the Hub report, never by label. Missing objects remain missing. Financial month coverage is required on both sides; monthly rows validate their own month. Incomplete vehicle time suppresses time-based changes. Missing workshop history is not zero. A zero baseline has an absolute difference but no relative percentage. Negative baselines use their absolute magnitude for the relative denominator.

The panel loads the main comparison separately from the main report. Internal revenue, billing balance and workshop comparisons load only when selected. Errors are isolated, retryable and do not block existing KPI cards. Cached source reports are scoped by tenant, user, generation, correction revision, period and filters.

Billing balance retains its own documented invoice-date/cost-booking-date basis and supported scope. It is not a cash-payment forecast. Internal revenue is already included in KPI revenue. The comparison does not add either amount to revenue or change financial facts, accounting exports, allocation rules or source documents.

Validation: production build and TypeScript; SQL assertions for amounts, percentage points, zero and negative baselines, missing snapshots, month coverage, canonical matching and missing workshop time; production browser checks on Overview and KPI.
