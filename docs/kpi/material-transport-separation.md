# Material and transport separation

The opt-in Hub report postprocessor uses an existing project unit (Elleholms:
4004, Grusmaterial). It runs before the prepared display projection, once per
generation. Selection changes still read precomputed data.

- NEXT material costs on vehicle carriers move to the configured material unit.
  The dated material account rule also takes precedence over the hired carrier
  default (9009); a quarry purchase is material, not hired transport. Explicit
  dated Dashboard category assignments retain their existing priority.
- Identifiable pure material article revenue moves to that unit.
- Bundled `inkl transport` / `ink transport` article revenue splits at purchase price; the remainder
  stays on transport. The engine reads the dated Workify rule name as source
  article names can omit “inkl transport”.
- Purchase evidence follows the existing receipt → order receipt → order comment
  → fraction-specific three-quarry average rules. Unread/conflicting receipts use the three-quarry average when all three dated prices and the source quantity exist. One quarry supported by interpreted order receipts is inherited as an explicit, traceable assumption. Special materials, unknown quantities or incomplete prices stay reviewable and unsplit.
- Receipt/list estimates NEVER create additional financial cost rows. NEXT is
  already the source of purchase costs. No double counting.
- Existing storage/project and Trading/tipping destination projects remain
  unchanged. Tipping gets the matching enabled project unit when the destination
  is unique. Unknown or ambiguous destinations stay unresolved.
- Source date and cost centre remain unchanged on each derived component.
- Original vehicle, unit, project, amount and purchase evidence are preserved in
  `_humla_material_separation`. Drilldown keeps both components traceable to the
  same Workify row; IDs are distinct using a `:material` suffix.
- Negative remainder is allowed when material purchase exceeds revenue; losses
  are not hidden by clamping. Credits require matching signs.

Settings are private, tenant scoped and disabled by default. Enabling for a tenant
requires an existing tenant-owned material unit and a valid-from date. This does
not change source imports, article rules, canonical identities or sync adapters.

Before activation, execute the migration and postprocessor inside a rollback
transaction against real prepared data. Verify revenue and cost totals per date
and cost centre; compare tipping rows unchanged; verify each split's sum equals
its original amount and purchase costs are not duplicated. Repeated application
to one generation must fail. Activate settings and request the ordinary report
sync, then verify both KPI and monthly report and their drilldowns.
