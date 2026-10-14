# Hub import reuse – integration contract (2026-10-14)

Status: **foundation implemented on feature branch; adapters not yet wired**.

This contract extends `AGENTS.md` / CORE-001 and is the same for manual Excel imports, vendor APIs, webhooks, and later reimports.

## Processing sequence

1. Preserve source system, tenant, external transaction ID and stable line ID in raw staging.
2. Resolve canonical identity via `hub_objects` and `hub_identity_keys`. Never use an external ID as Humla's shared identity.
3. Apply date-valid, confirmed mappings from Hub's persisted rule tables. Suggestions, display names, registration plates and historical patterns are evidence, not confirmations.
4. Reconcile stable transaction/line identity against previous imports. Equal identity + equal content version = duplicate, count once. Equal identity + different content version = corrected line, review/replace atomically; never sum both.
5. Retain unique valid transactions, including those awaiting uncertain economic allocation, in explicit unallocated/review buckets. Do not silently lose revenue/costs.
6. Apply economic-unit and cost-center mappings at event date. Persist rule ID and applied version for an auditable historical result.
7. Aggregate canonical Hub facts once, then expose to KPI/Transport/other consumers. Dashboards must not privately recompute source mapping.

## Existing storage to reuse

- Identity: `hub_objects`, `hub_identity_keys`.
- Match/learn/review: `hub_economic_match_rules`, `hub_economic_allocation_learning`, `hub_economic_allocation_review`, `hub_allocation_mapping_rules`, `hub_allocation_mapping_events`.
- Workify driver/vehicle: `hub_workify_driver_vehicle_rules`.
- Imported source rows: `kpi_import_rows`, `kpi_import_batches`. Treat old rows without stable source transaction identifiers as candidates for review, not automatically independent transactions.
- KPI compatibility: maintain existing KPI mappings during migration; update Hub's canonical mapping as source of truth.

## Deployment gate (not yet satisfied)

- [x] Pure, source-neutral import identity and reconciliation guardrails in `src/lib/hub/import-reuse-contract.mjs`.
- [x] Regression tests for overlapping Excel/API imports, corrected rows, missing identity and conflicting rules.
- [ ] Wire each active Workify, Next, TransPA and other adapter to the shared contract.
- [ ] Backfill persisted transaction/line identity and content fingerprint; devise a reviewed policy for legacy rows lacking stable IDs.
- [ ] Execute database-backed, transactional upsert and corrections (the pure helper only reconciles its passed batch).
- [ ] Confirmed user mappings persist in Hub and are reused at next import with valid date bounds.
- [ ] Verify all dashboard and KPI calculations consume unique Hub facts rather than summing overlapping raw `kpi_import_rows`.
- [ ] Full historical regression for 2026-09 Workify overlapping imports and Next (71)/(72) without changing finance totals until verified.

No schema change, production deployment, or retrospective mutation is included in this branch. Release must not be declared complete until these adapter and persistence checks pass.
