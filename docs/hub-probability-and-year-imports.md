# Hub probability routing and fiscal-year reimports

Financial validity and routing confidence are separate. A valid financial fact
does not leave totals merely because its unit is uncertain. The canonical dated
Övrigt collection remains the fallback. Duplicate protection is not weakened.

## Evidence and routing

The existing `hub_match_runs` / `hub_match_evidence` ledger is reused; no parallel
identity catalog is introduced. Typed source fields resolve to canonical Hub
objects before dated economic-unit membership is evaluated. Arbitrary values
such as amounts and account numbers cannot act as external identity seeds.

Signals currently collected are explicit vehicle identity, NEXT project identity,
document registration text, an exactly identified driver's same-day TransPA
activity, earlier observed driver activity, same-date/order/customer transport
context, and patterns supported by distinct human decisions. Material and tipping
are not inferred from another transport row on the same order. Explicit article
rules and existing confirmed allocations retain precedence.

Related signals are grouped by family and provenance. Repeating the same signal
does not increase its contribution. A strong automatic match requires a unique
registry anchor or independent temporal agreement, support at least .92, and a
.12 margin over the runner-up. A probable match requires support at least .70,
no conflicting anchors and a .05 margin. Both can route the derived fact; probable
matches are explicitly provisional. Ties and missing evidence retain Övrigt.
These are heuristic support scores, not calibrated probabilities.

No probabilistic decision creates permanent identity keys. Human decisions are
not overwritten. Learned patterns must have distinct human confirmations before
reuse; source rows that were probabilistically routed cannot teach same-order
context. Explicit project exclusions apply to all candidate sources.

The worker evaluates a bounded first pass of 100 eligible facts per new report
generation, prioritizing Workify transport. Other facts still have their fallback
mapping and remain in financial totals. The evaluation records its coverage in
job metrics; it does not claim every historic fact was examined. The private
batch function supports further bounded passes. `hub_match_prepared_fact_v2`
exposes authorized on-demand evaluation against authoritative prepared facts.

## Publication safety and reliability

Only derived routing fields and evidence change. A before/after fingerprint
checks count and amount per date, kind, cost centre and category. Display rows
must be synchronized one-for-one. The original imports stay immutable. Repeated
application to already evaluated facts is a no-op.

Confirmed-unit routing first materializes eligible facts, splits project/vehicle
joins and synchronizes only changed records. The worker refreshes statistics
before unit routing and records individual validation/allocation/matching stages,
so a routing timeout is no longer mislabeled as a distance calculation failure.

## Whole-year uploads

Unchanged rows are deduplicated independently of physical file row order.
Occurrence capacity preserves genuinely repeated identical source lines. New
transactions proceed to the existing classification and distribution pipeline.

Workify changes are isolated to the affected order. NEXT changes are isolated by
fiscal year, voucher, project and account (or date/project/account when a voucher
is unavailable). If old content disappears while new content appears in the same
source group, it is an ambiguous revision, not automatically additional money.
The incoming original is retained in observations; old authoritative amounts stay
in effect until source identity/revision is resolved. Other independent source
groups still import. Missing rows do not implicitly delete older transactions.

NEXT uses the existing central importer behind a private revision guard, retaining
its normalization of routing-only review errors, concurrency lock and idempotent
batch receipts. Workify retains its existing immutable status observations and
source fingerprints. An import may contain accepted new financial rows **and**
revision exceptions; `changedRows` / `changes` report the distinction.

## Verification

`supabase/tests/hub_multisignal_mapping.sql` checks provisional single signals,
independent agreement, repeated-signal invariance, ties, identity conflicts,
human-confirmation preservation, financial invariance and anonymous denial.

`supabase/tests/full_year_incremental_imports.sql` checks both source systems with
reordered snapshots, genuine repeated lines, new rows beside edited source groups,
same-batch retries, status changes and credits. All synthetic data is rolled back.
The former all-or-nothing Workify edit expectation is deliberately superseded:
only the ambiguous order is held, not unrelated new transactions in the file.

## Deployment checkpoint, 2026-10-18

Migrations through `20261018001000` are live. The report worker successfully
published a new generation and evaluated 100 facts: 4 strong matches, 9
provisional matches and 87 retained fallbacks, with financial inclusion unchanged.
Both regression suites passed before the additional status-preservation assertion.

`20261018002000` is prepared but **not applied**: the migration approval request
expired twice. It preserves `needs_review` through Workify's downstream mapping
resolver. Until applied, source revisions are retained safely in provenance and
observations, but the batch status can incorrectly return to `completed` after
mapping its independent accepted rows. Apply this migration and rerun the full-year
test, including its new resolver-status assertion, before calling that status issue
fixed. No financial amount is overwritten by this status issue.
