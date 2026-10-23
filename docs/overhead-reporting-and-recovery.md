# Overhead reporting and dashboard recovery

Overhead is the sum of verified monthly management costs (including payroll on-costs) and other overhead. Management is included once. Indicators show total SEK, management SEK, each cost's share of revenue, management's share of overhead, and cost per billable hour. Monthly/YTD metrics are produced in Hub and consumed by Dashboard and report exports.

There was no populated management-cost or overhead evidence in the existing settings. Unknown costs remain null, rather than zero or a guessed salary. Managers can record both monthly amounts and a source reference for one selected cost centre. Changes have before/after audit records and increment the correction revision. These classification indicators do not add another cost to financial totals.

Billable hours use unique accepted Workify source rows with an hour unit and nonzero published revenue. Internal Elleholms Maskin customers are excluded, and credit quantities reduce hours. Raw quantity is normalized when the legacy import quantity column is absent. Compact prepared evidence prevents repeated full-source reads. Unknown hours and zero denominators return missing indicators.

Department overhead is not automatically distributed to a selected vehicle/project/group without a verified allocation basis. The UI explains that scope limitation.

Recovery: internal-transfer classification no longer performs a permission-checked material-scope lookup for each order row. The financial overview defers the slower internal summary to an independent request. The overview has a tenant/generation/revision/scope cache and a concurrent-build guard; server cache misses are coalesced per authenticated user. Browser fetches and refresh actions now have finite waits.

Validation: TypeScript/build checks; live month-hour coverage; rolled-back overhead evidence test verified sum, revenue percentages, and per-hour amounts; full-year Hub read returned financial metrics after the recovery. No test cost evidence was retained.
