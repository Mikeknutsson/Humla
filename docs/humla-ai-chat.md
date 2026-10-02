# Fråga Humla

Dashboard route `/kpi/ai` and POST `/api/ai/chat`. Entry point stays in the Dashboard refresh bar. AI SDK 7 ToolLoopAgent uses Vercel AI Gateway runtime OIDC, with optional server-only `AI_GATEWAY_API_KEY`. Optional `HUMLA_AI_MODEL` overrides the verified model ID.

## Evidence and scope

Every request resolves the authenticated user's active tenant and requires `kpi.read`. Hub search and rate reservation are SECURITY INVOKER RPCs with explicit permission checks, existing RLS, and authenticated-only execute grants. No service-role client or arbitrary SQL is exposed to the model. Search returns allowlisted business fields, not connection credentials, raw integration envelopes, HR identities or account authentication data.

`searchHub` searches valid KPI import rows in completed/needs_review batches and business Hub objects. It matches all search terms case-insensitively in original customer/article/comment and business fields; 30 results per page. Vehicle meter readings use the existing asset-to-vehicle relationship, without modifying canonical identities. Source results show original row amounts and import status; a Workify invoiced flag does not establish a complete accounting invoice. Full document contents not ingested into these sources are outside this version.

`kpiReport` calls existing Hub analysis RPCs and the per-user daily report cache. Actual selected months, cost centers and groups stay intact. Financial totals are computed by Hub. Source evidence pages stay in Dashboard and check current authorization on every visit. Each answer's source cards are attached to real retrieved records, and the prompt requires fresh retrieval on follow-up questions.

## Limits and verification

Maximum 8 requests/minute and 100/rolling24h per user, atomically reserved in Hub. At most 16 messages / 24,000 characters; 4,000 per message. At most six agent steps, 1,800 output tokens per step, 110-second timeout. No automatic data writes from the chat. Runtime logs exclude conversation content and search results.

Real-data verification: Linnestofta Maskin + aska + IFA matches Workify order43308, amount11,844SEK, original price420/ton and28.20ton, marked invoiced2026-07-06. DFC86A meter lookup resolves its asset ID. Anonymous and foreign-tenant access rejected; ninth request/minute rejected in a rolled-back test. Build and TS/ESLint pass. Production AI roundtrip is separately verified, not inferred from database tests.
