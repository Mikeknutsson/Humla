# Monthly meeting reports

The dedicated `/kpi/manadsrapport` page loads the monthly report without first loading overview/fleet analysis. Monthly JSON, Excel and meeting PDFs consume the same tenant-authorized Hub report. The two-department PDF prepares KST 20 and KST 30 sequentially.

`private.hub_kpi_monthly_report_cache` is keyed by tenant, active generation, correction revision, fiscal year, month, cost center and filters. Each public RPC call checks `kpi.read` before cache access. The uncached base function is private and unavailable to authenticated/anonymous callers. A transaction advisory lock prevents duplicate preparation of an identical report. No missing-data exception is converted to zero.

Confirmed supplier classifications use exact NEXT supplier evidence. Their scope is NEXT costs; individual fact rules retain priority. Erik Ivarsson maps to the canonical LMT31J unit/vehicle and personnel category. Kofsa retains each original project while using personnel category. The confirmed Kofsa/Fredrich relationship is an Assignment between canonical Supplier and Person objects. NEXT hours stay separate from invoice costs; no invoice hours/rate/service period are inferred.

`private.hub_kpi_publish_supplier_categories_v1` publishes only category corrections to already-prepared source facts and their display projection. Original files, monetary values, dates, projects, vehicle/unit allocation and row counts are preserved. The private audit retains before/after category, source rule, actor and conserved financial context. A correction revision invalidates monthly and Next report caches without a full report rebuild. Reapplying an unchanged classification is idempotent.

Known Workify period controls are displayed as reconciliation metadata. A difference marks revenue and result as partial in the report and is shown in the meeting PDF. A manually reported total never replaces source revenue automatically. September 2026 remains preliminary pending order-version reconciliation.

Validation: PGlite cache/permission regression test, production before/after category audit, idempotency query, cached report query plan, TypeScript/lint/build, and PDF render inspection. Full background preparation was canceled after load problems; existing working generation retained. Further full-job optimization remains separate from the meeting report cache.
