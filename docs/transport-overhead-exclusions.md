# Transport overhead exclusions

User-confirmed material and tipping/trading units in KST30 are excluded from monthly overhead and shared supplier management allocations from the existing material policy start date. Exclusions are persisted against canonical EconomicUnit IDs in a private RLS table. The material unit is also excluded for its historical KST20 entries. Other KST20 units retain their existing eligibility. Direct source costs and internal material profit corrections remain unchanged.

Removed overhead is redistributed among the existing remaining revenue-bearing recipients using each original allocation method. Annual company revenue and costs remain unchanged. The nightly worker prepares registered material value, refreshes the common supplier pool, then allocates monthly overhead so replay and nightly revenue bases agree.

Validation: no excluded unit receives monthly/shared supplier overhead; annual financial totals conserved; display facts synchronized; replay stable; KST20 nonmaterial eligibility preserved.
