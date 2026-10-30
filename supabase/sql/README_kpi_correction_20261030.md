# KPI correction, 30 October 2026

Base: published commit 7d1e5906e5d1e57f27ccffb0376b3a25b1f9b3db.

The gauge uses -50% to +50%. Exact values remain visible outside the scale.

The SQL files are prepared, **not applied or execution-tested**: the Supabase connector's write confirmations expired / returned conflicting request metadata. Do not mark this correction as published.

Run these scripts together in a single transaction, first with ROLLBACK for validation, then COMMIT after successful checks:
1. fix_saw_supplier_configured_share.sql
2. default_kpi_margin_twenty_percent.sql
3. repair_saw_supplier_active_generation.sql

The repair retains 25% on KST10 and moves the old shared Transport portion to Sawing. It asserts unchanged financial totals per fiscal year and kind. The function keeps its existing kpi.manage authorization. Existing explicit targets retain precedence over the 20% fallback.

Read-only source check (14 lines) for the active report:

| Fiscal year starting | Source | Proposed Sawing | Proposed KST10 | Difference |
| --- | ---: | ---: | ---: | ---: |
| 2025 | 833122.77 SEK | 624842.10 SEK | 208280.67 SEK | 0.00 SEK |
| 2026 | 79900.00 SEK | 59925.00 SEK | 19975.00 SEK | 0.00 SEK |

After applying, verify the per-source branch sum, display fact consistency, absence of supplier-common rows, authorization, scorecard targets, and repeat-run idempotence. Bump the report correction revision only after successful verification if cache invalidation requires it.
