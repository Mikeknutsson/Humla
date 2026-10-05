# Interna körningar / ekonomins omföringsunderlag

Dashboard: `/kpi?view=internal`. Exact Workify customer `Elleholms Maskin AB`; STENA excluded. Period follows occurred_on / Artikeldatum, including selected fiscal months. Separate transport/material/tipp categories use dated Hub article rules. Missing categories are not guessed.

Source and receiver centers are separate: dated vehicle registration classification versus dated Littranummer project classification. Canonical Vehicle/Project object IDs resolve only through existing confirmed Hub identities; ambiguous or absent links remain reviewable in the existing Control Panel. No new guessed identity registry, automatic BAS account mapping or bookkeeping is introduced.

All candidate rows remain visible. Only valid, invoiced, uniquely identified, fully linked rows can be exported (maximum 2,000 per export). Legacy row identity conservatively uses order/article/date/vehicle when no external transaction ID exists. Indistinguishable repeats are blocked, not silently dropped. Changes after export show `changed` and cannot be re-exported automatically.

The persistent ledger stores a snapshot, export ID, author and timestamp. A transactional tenant lock plus unique source key prevents double export. Downloads can be repeated by export ID without reserving rows again. `Omfört` requires explicit confirmation and a booking reference after accounting performs the transfer. Nothing is automatically posted or added to existing KPI revenue; this is not a consolidated external-revenue view.

Read RPC and table policies require `kpi.read`. Ledger writes require `kpi.manage`, are guarded in a non-exposed private function and cannot be performed through direct Data API table writes. POST rejects cross-origin requests. No service credential is exposed.

Excel has summary by centers/vehicle/project/category and complete selected order rows with canonical object IDs and source references. Browser signed-in verification is separate from database and production-build tests.
