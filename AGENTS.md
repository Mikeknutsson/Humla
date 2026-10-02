# Humla – mandatory architecture rules

These rules apply to all new code, refactors, integrations and dashboard/KPI work in this repository.

## CORE-001 – Canonical Humla Identity

**Status: LOCKED / CORE**

External systems must never use each other's identifiers as Humla's shared identity.

The mandatory flow is:

```
Source system external ID
        ↓
Integration adapter / mapping in Humla Hub
        ↓
Canonical Humla-ID
        ↓
Humla domain logic / history / relationships
        ↓
Consumer adapter
        ↓
Consumer system external ID
```

### Required implementation behaviour

- Humla Hub owns canonical identities.
- Internal Humla relations and new cross-module logic use canonical Humla-ID/object IDs.
- External identifiers such as NEXT project numbers, registration numbers, TransPA employee IDs, Workify references, Fordonskontrollen IDs and Scania IDs belong to the integration/identity mapping layer.
- Do not introduce new direct system-to-system mappings as the long-term architecture.
- One Humla object may have several external identities, but one canonical Humla identity.
- Confirmed manual mappings in Dashboard/Control Panel must be persisted as reusable Hub identity knowledge, not only as KPI configuration.
- Mapping history must be traceable and date-versioned where the relationship can change over time.
- Uncertain matches must remain unresolved/reviewable; never silently create a permanent identity from a guess.
- KPI/Dashboard is a consumer/display layer. Identity resolution, mapping and business calculations belong in Humla Hub/backend.
- A consumer system must be replaceable without forcing changes in unrelated integrations.

### Compatibility rule for the current KPI implementation

CORE-001 is introduced additively. Existing KPI mappings must continue to work while they are migrated to canonical Humla identities. Do not delete or rewrite working historical KPI mappings merely to satisfy the new model. New confirmed mappings should populate the Identity Engine as well as any compatibility mapping still required by the current KPI implementation.

### Canonical storage

The current canonical identity foundation is `hub_objects` + `hub_identity_keys`. Extend this identity layer rather than creating a parallel identity registry.

The database also contains the permanent architecture record `humla_architecture_rules.CORE-001`. Code changes that conflict with CORE-001 require an explicit architecture decision rather than a local workaround.
