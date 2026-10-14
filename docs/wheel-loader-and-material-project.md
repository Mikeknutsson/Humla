# Wheel loader article routing and material project

An explicitly confirmed Workify article rule matches the literal substring in the article name, ignoring case. It points to an existing canonical EconomicUnit. The dated unit version supplies its confirmed main vehicle, project and business group; the dated project registry supplies its cost center. Conflicting targets or missing/ambiguous dated recipients stop the update for review.

The Hub publication worker applies the rules to revenue only. Existing published rows are corrected in place in the full and display projections. Audits retain previous values. Source imports, amounts and fact identities are unchanged. The migration installs no tenant-specific rule: the maintenance script resolves confirmed objects within the caller's tenant and records the explicit approval.

Material separation settings now use the confirmed manual Grusmaterial economic unit instead of the older imported placeholder. Existing material facts are consolidated onto that canonical unit; amounts, cost centers and source documents are preserved. Future material separation and project cost allocation reuse the same canonical ID.

Both Overview and KPI display the Grusmaterial project card using the canonical material unit ID supplied by Hub. Revenue, costs, result and margin come directly from the filtered Hub report. Each figure links to its underlying rows or unit details. The figures are already included in report totals.

Validation: production build/TypeScript; financial row-count and amount conservation; complete routing of matching published articles; no unmatched target units; material sums checked against published project facts; rollback-only SQL tests for case-insensitive substring matching, revenue-only scope, conflict handling and idempotence; browser checks of both views and drilldown.
