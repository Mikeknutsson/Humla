# Unit period detail

Every configured KPI unit has a Granska action under Enhetsmappning. The detail panel supports financial year (tenant settings), calendar month, Monday–Sunday week and day. Clicking a period narrows the date range and advances to the next level; Back restores the prior range. Boundary weeks are clipped to the selected range.

The invoker RPC uses the same exact unit resolution and account mapping rules as kpi_unit_report. Conflicting units, invalid transactions and unmapped/excluded accounts do not contribute. Vehicle-result inclusion still applies separately. Transaction pages contain 50 rows, original values, file name, original amount and actual contribution to result. No data is changed.

Validated in a rolled-back authenticated SQL transaction: same 600 total at all four grains, excluded invalid row, clipped cross-month week and transaction pagination. Build and lint passed. An authenticated production browser session was unavailable; this remains a verification limitation.
