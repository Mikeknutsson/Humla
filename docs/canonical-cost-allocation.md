# Canonical cost allocation

The prepared Hub pipeline now applies approved `hub_cost_allocation_rules` to canonical EconomicUnit recipients before publishing. The source adapter resolves exact project/vehicle identities through the existing Hub identity catalog. Recipient periods, enabled state and excluded units are evaluated on each cost's date. Compound units receive one share; their component vehicles do not receive additional shares.

Selected rules use their approved canonical recipient IDs. General transport rules accept own trucks in the dated KST registry, exclude trailers, tractors and hired units, and also recognize truck recipients explicitly confirmed in the existing truck-group rules. No guessed identities are persisted.

The manual personnel rule requires one verified vehicle/person/project identity. Missing or conflicting identities remain on the original cost with a review marker. Rules without matching costs remain active with zero effect.

The allocation replaces derived source facts with their shares, retaining the full source fact and rule snapshot in a private audit table. Amount, category, date and cost centre are conserved, including credit rows and last-share rounding. Originals are never changed. Repeated application is a no-op. Overlapping rules abort the transaction.

Published status is exposed through a permission-checked RPC and displayed in Hub cost control and KPI reconciliation. Amounts there cover the full published history. KPI, monthly reports and exports read the same prepared facts. Correction revision invalidates cached reports after targeted publication; no full worker rebuild is required.

Deployment migration consolidates the engine and performance refinements applied during validation. Existing rules were activated separately after a rolled-back test and conservation checks. Regression SQL verifies conservation, dated recipients and idempotence. The worker runs the same engine after preparing the display facts and validating source reconciliation.
