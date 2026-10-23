# Shared worked time

Monthly report and unit comparisons show one Arbetad tid row. Hub adds approved
NEXT project time to TransPA after canonical person/day overlap subtraction,
apportioned over that person's NEXT rows. NEXT import copies are reconciled
before aggregation. Absence, OB supplements and REP time remain separate.
Units without a vehicle keep project hours and their cost/hour; those hours
do not create fleet utilization without a vehicle link.

Fleet utilization and aggregated vehicle cost/hour use only vehicles with
positive hours in the exact selected period. Both capacity and financial
numerators use that vehicle scope. NEXT-only registered vehicles get the
selected weekdays/holiday calendar capacity. Zero/missing time yields null
rates, while the vehicle's ordinary economic totals remain visible.
The shared projection runs for current and prior fiscal years and exact daily
filters, with no changes to financial facts, salaries or import mappings.

Validation: pure SQL regression covers positive/zero/missing time, NEXT-only
capacity, removing costs of zero-hour vehicles and category rates. Live rolled
back comparison for September 2025/2026 and KST 20/30 confirmed identical
revenue, total cost, fuel, payroll and internal revenue before/after. September
2025 Transport: 107 overlapping hours removed; September 2026: 23 vehicles with
4447.4 operating hours and 4048 capacity hours. Current Sortergården has 250
NEXT project hours with no registration; these do not invent a vehicle link.

Monthly API cache key is v10 combined-time, and Hub correction revision changes
invalidate prior overview calculations. Full fiscal-year import protection and
permanent mappings are unchanged and remain active for new imports.

Full-year performance correction: canonical person keys and repair facts are
materialized once, native overlap scans the selected dates/months, and vehicle
categories are aggregated once rather than scanning facts for each vehicle.
The NEXT helper owns its planner settings instead of inheriting the snapshot's
join configuration. Financial filters and time formulas are unchanged.
Cold full-year requests have a 45-second RPC budget; completed reports remain
cached per tenant, generation, revision and exact scope. The reported 2025/26
whole-year selection was executed successfully as authenticated, with 42939.58
worked hours and both reconciliation flags true, then committed to scope cache.
