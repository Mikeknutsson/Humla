# Shared economic units

Confirmed manual KPI units are represented by `EconomicUnit` objects in `hub_objects`. The existing unit UUID is retained as the canonical Humla ID and the `kpi_unit_id` identity key is the compatibility adapter. Imported NEXT project aliases do not create extra units.

Each object contains all dated configuration periods and components. Exact existing identity keys and redirects resolve members to canonical Vehicle, Project and Person objects. Missing or ambiguous identities remain visible for review; names alone do not create identities. NEXT cost-project numbers may identify Vehicles, and must not create competing Project objects.

Changes to units, periods and components sync in the same transaction. Changed object payloads archive the preceding version in `hub_object_versions`; unchanged payloads are idempotent. New exact source keys refresh affected units. Historical KPI mappings and financial facts are not rewritten.

`hub_economic_units_catalog_v1` requires an authenticated caller with tenant-specific `kpi.read` permission. The shared register is available through `/ekonomiska-enheter` and `/kpi/ekonomiska-enheter`, including units without period transactions. Dashboard financial drilldown keeps its existing prepared financial generation.

Verification: `scripts/test-canonical-economic-units.mjs` exercises stable IDs, temporal memberships, incomplete identities, automatic identity refresh, idempotency, imported alias exclusion and tenant/anonymous access.
