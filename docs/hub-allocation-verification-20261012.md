# Hub allocation verification — 2026-10-12

Status: comparison mode only. Standard KPI prepared-report totals have NOT been switched to the new ledger.

Implemented centrally in Supabase:
- Economic fingerprints ignore export status and derived allocations. Source multiplicity is preserved; overlapping copies are counted once.
- NEXT ingestion separates financial validity from allocation status and is atomic and tenant-locked.
- Confirmed rules use canonical Hub object IDs, date validity, overlap-conflict checks, idempotent confirmation and an immutable audit log.
- Existing confirmed KPI allocations are reused through a Hub compatibility adapter. 139 of 141 targets resolve; two remain unverified.
- Candidate scores include canonical source registration/project identities, dated confirmed rules, driver name, TransPA same-day evidence and preceding 90-day driver/project/customer/supervisor history. Scores are NOT calibrated probabilities. No guesses become permanent automatically.
- Read-only reconciliation includes unallocated amounts and separately exposes duplicate, withdrawn, already-accounted and invalid rows with original-row drilldown.

Verified:
- Production build and parser capacity tests (50,000 rows; larger files explicitly rejected).
- Transactional rollback tests cover overlap, real identical multiplicity, credits, permanent mappings, retry, conflict, audit and tenant isolation.
- September source totals remain unchanged when compatibility mapping is applied.
- Compact report projection preserves the entire September report JSON digest before/after. Financial audit details remain outside source control.

Original Workify audit:
- An original full-year file contains rows omitted by the legacy 20,000-row cap, which also counted continuation rows.
- Original JSON multiplicity and binary SHA256 were verified against the saved source; amounts were independently reconciled.
- Recovery preflight distinguishes zero-value rows, already-imported financial rows and genuinely new source occurrences.
- Actual ingestion was tested with rollback, with zero changed rows. No recovery has been committed to financial data yet.

Remaining rollout gates:
- Reconcile NEXT originals and cross-source Workify/NEXT revenue overlap before changing standard KPI totals.
- Review 46 registration numbers associated with multiple canonical Hub object IDs; do not silently merge historical identities.
- Verify live authenticated browser/API flows and full-year latency under load.
- Complete controlled original-file recovery, compatibility write-through and exact TransPA interval coverage. Same-day evidence is explicitly not interval proof.
- Preserve all historical original rows and maintain rollback capability for report-engine activation.
