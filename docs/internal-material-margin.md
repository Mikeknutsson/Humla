# Internmaterial: internpris minus inköp

Overview displays the difference between billed internal material revenue and purchase evidence for the same published material rows, scoped to the report filters and active generation. All calculations live in Hub.

The comparison uses the purchase evidence saved in `_humla_material_separation.purchase`, preserving the published report basis. It does not substitute all Grus project costs, use a total-revenue remainder, or assume that missing purchase evidence means zero cost. Both credit amounts retain their sign; conflicting purchase/sale signs are review items. Source rows are deduplicated before aggregation.

Material bundled with transport is excluded and counted separately. Its published material revenue is allocated at purchase cost; subtracting that cost again would create a misleading zero material margin. A separate selling price is required for a pure material comparison.

Price-list and average-cost evidence is explicitly preliminary, not a claim of matched supplier invoice costs. The panel shows compared selling price, purchase cost, difference, margin percent, estimated row count and missing coverage.

September 2026, KST30: 82 compared rows, selling 429506.16, purchase 337420.14, difference 92086.02, margin 21.44%. 80 rows have estimated/preliminary prices; 22 rows selling 79329.52 are excluded for missing usable evidence. Compared selling plus excluded selling reconciles to the 508835.68 material revenue card. No bundled rows in this selection.

Validation: production RPC completed within the authenticated 8-second statement timeout; rollback integration checks cover reconciliation, cost-only scope, signed credits, conflicting signs and bundled transport exclusions. Next.js webpack production build passed.
