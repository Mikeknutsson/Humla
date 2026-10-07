# Fordonskontrollen meter worker

Authenticated by the existing Humla worker key, verified inside the function.
The service-only job RPC derives the tenant from the configured connection.
Credentials remain in the configured credentials store; they are never returned.

The private cron tick starts daily at 03:00 Europe/Stockholm. Every five minutes
it also resumes incomplete jobs, with leases and bounded retries. Each invocation
fetches at most six 100-record pages and imports 50 records per RPC transaction.
Page cursors advance only after all records are imported or retained for review.
Upstream errors and validation failures leave the page replayable. A one-day
watermark overlap tolerates recent late arrivals; canonical aliases make replay
idempotent. Unmapped evidence is retained in Hub review, never guessed.

The overview's `previous` field is now explicitly scoped as
`financial-comparison-v1`: financial metrics, period, filters and coverage only.
The current overview and standalone full snapshots keep operational detail.
Known consumers use previous revenue, result and margin; all those numbers and
the coverage gate were regression-compared with the original full snapshot.

Database replay checks: `supabase/tests/hub_meter_sync_regression.sql`.
