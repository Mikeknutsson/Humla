# Supplier cost allocation

The existing confirmed supplier/account/project scope is preserved. Direct saw activity receives 50 percent, enterprise cost center 10 receives 25 percent, and the remaining 25 percent is distributed equally among date-valid enabled transport economic units with positive revenue in the source invoice month. The saw unit participates in the common transport pool when eligible; its direct 50 percent is therefore separate from any shared overhead allocation.

Derived common rows are replaced deterministically on replay. Original source evidence and invoice amount are retained, while rounding remainder goes to the last common recipient. Every original invoice cost is conserved exactly, including credit amounts. Missing eligible recipients abort rather than dropping the cost. Public display facts update with the derived facts. Hooked into the existing saw allocation stage for nightly rebuilds. No source imports or revenue are changed.

Verified per-source conservation, idempotent replay, direct and enterprise shares and prepared/display agreement. Prior confidential person-cost configuration is untouched.
