# AMA / BSAB classification for Humla → Next project budgets

## Official sources and licensing

- Svensk Byggtjänst provides searchable AMA Anläggning online, including AMA, RA and MER.
- BSAB 96 tables can be downloaded through the official BSAB service, but embedding/reusing the tables in software requires a **nyttjanderättsavtal** with AB Svensk Byggtjänst.
- Do **not** scrape or replicate the complete AMA/RA/MER texts or BSAB tables into Humla without explicit applicable rights.
- Import the user's own priced bill of quantities / offer document and retain its source references; this does not imply a license to redistribute the normative AMA texts.

Official links:
- https://byggtjanst.se/tjanster/ama/ama-anlaggning
- https://bsab.byggtjanst.se/
- https://byggtjanst.se/tjanster/ama/ama-beskrivningsverktyg

## Canonical model

`hub_ama_catalog_entries` holds tenant-scoped, edition-specific classification codes. It is intentionally empty until a permitted data source is agreed. Source and usage_rights are mandatory; entries are never quietly invented.

An extracted quantity row should preserve:
- immutable source document identifier; page, table, row, and quoted provenance
- extracted code exactly as supplied, classification system and edition (or unverified)
- free-form description from the customer's document, unit and quantity
- measurement basis / geometry (length, width, depth; conversions e.g. m3↔ton via reviewed density)
- price and cost components (material, labor, machine, transport, tipping, subcontractor, markup)
- confidence and review status
- Next external project ID mapped through canonical Humla project identity

AMA technical specification ≠ pricing. MER is where measurement/compensation rules are referenced, but the correct generation and project-specific contract must be checked.

## Safe export contract to Next

1. Upload project documentation or an offer; create a versioned *draft* calculation.
2. Detect and associate source AMA/BSAB code and edition; if absent, keep code unresolved.
3. User verifies quantities, assumptions, cost/price and selected project.
4. Convert the approved calculation to the Next budget line structure **only after verifying API schema and test permissions**.
5. Preview all changes before any Next write; idempotency key = tenant + project + approved budget revision + line id.
6. Record every Next external budget ID, response, source and reversal/retry metadata through Hub; never duplicate on retry.
7. Keep proposal/contractual sales-price calculation distinct from cost-side production budget.

## Release status

Only a tenant-scoped, read-only classification schema foundation is added. No licensed catalog is populated; no Next budget API writes are activated.
