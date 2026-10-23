# Internmaterial: internpris minus inköp

All published invoiced internal material rows in the selected report scope are included. Calculations live in Hub; Overview consumes the summary and expandable per-row evidence.

Use the purchase evidence saved in `_humla_material_separation.purchase` where available. When the published evidence has no amount, use the existing approved `hub_kpi_internal_purchase_costs_v1` overview-estimate rule, in batches of up to 1000 source row IDs. This first uses an available price for the material fraction, then an average for the same unit across available standard quarry materials. The original unresolved evidence is retained in the published facts. Raw imports and financial totals are unchanged.

Source rows are deduplicated before aggregation. Both credit amounts retain their sign. Conflicting sale/purchase signs remain visible as unresolved cost. All selling prices remain included; if any costs cannot be calculated, the total purchase cost and margin are null rather than silently treating unknown cost as zero.

Bundled material/transport rows use their original full billed price once. They remain included and explicitly indicate that their difference also contains transport. The ordinary KPI material component remains unchanged. No bundled rows exist in the September KST30 selection.

The expandable table shows date, order, article, billed price, calculated purchase cost, difference, estimate flag, price source, rate, quantity and evidence notes.

September 2026, KST30: all 104 rows, billed 508835.68, purchase 394985.05, difference 113850.63, margin 22.37%. 102 rows use estimated/preliminary prices. Of these, 22 rows billed 79329.52 use supplementary estimates costing 57564.91; none are excluded.

Supplementary evidence gaps: 9 rows 0-150/200 (ambiguous fraction), 5 rows 16-22/32 (ambiguous fraction or unresolved evidence), 2 Stenmjöl, 1 32-63, 1 8-16 (supplier/price not sufficiently resolved), 4 Annan (material type missing). Rates remain explicitly estimates, not verified supplier invoice costs.

Validation: production summary RPC completed within the authenticated 8-second statement timeout. Rollback integration tests cover coverage reconciliation, scope, signed credits, conflicting signs, full inclusion and bundled-price handling. Next.js webpack production build passed.
