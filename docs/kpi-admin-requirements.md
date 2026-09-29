# KPI administration: migration requirements

Source: user-provided legacy KPI settings, 2026-09-29.

- KPI units group multiple projects, registrations and employee references; shared costs are not vehicles. No automatic allocation to trucks.
- Project overview is a periodically updated reference register, distinct from monthly transaction imports. Preserve source file and row, project category, project owner and ambiguous vehicle relationships. Do not infer access rights from an upload alone.
- Workify article allocation determines whether revenue follows the project or performing vehicle. Existing 15 rules have not been exported or migrated.
- Monthly fixed costs require target unit, cost type, amount, effective months, notes and duplicate protection. The pasted legacy screen repeats SCO308 depreciation of SEK 8,750 six times; do not seed SEK 52,500 without reconciliation.
- Salary costing: source actual TransPA wage amounts and employer costs only after field coverage and person identity have been verified. Time/tachograph evidence is not wage cost. Legacy fallback inputs were monthly salary 34,000, month hours 174, employer cost uplift 48.7%, overtime factor 1.5 and overtime above 40 hours/week. These are reference requirements, NOT active settings or legally validated payroll rules.
- Hub owns integrations and secrets; KPI must not create parallel Fordonskontrollen, B.SMART, PS Olja or TransPA connections. No secrets shown in KPI.
- Future access control: main admin global access; others receive union of explicitly authorized projects and vehicles. Enforce on backend detail, aggregate and export paths before providing limited-role access. Existing kpi.read is tenant-wide, not object-level authorization.
- Rule changes need provenance and history; immutable historical calculation snapshots remain a separate requirement. Current KPI unit edits are audited but recompute history within the selected validity interval.
- Project overview identified 139 single-registration projects, five multi-registration projects and 193 without a registration. Sixteen of the singles have sale/closure flags. No source mappings have been activated merely from these counts.

Implemented in this increment: editable KPI grouping with three types, dated reference lists, atomic edits with revision checks, audit events, conflict exclusion and separate group report. Does not change canonical person identity or existing top-level KPIs.
