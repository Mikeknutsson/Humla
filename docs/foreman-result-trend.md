# Foreman result trend
The foreman page shows a compact cumulative result chart immediately after the existing period picker and a fourth summary tile, Resultat %, immediately after Resultat. The read-only chart supports pointer inspection, a native keyboard/touch range control and an expandable daily data table. It follows the same resolved from/to and selected profile as the existing report.

## Financial meaning
Hub returns daily cumulative revenue, costs, result, margin and target. Result includes all scoped costs, including own costs on units without revenue. For Sortergarden the owner-set whole-area goal is 20% (KST20), saved with updater, timestamp and reason in private.hub_cost_center_margin_targets_v1. This whole-area goal applies in the trend only for a profile scoped to that entire single cost center, so individual unit targets remain intact (e.g. Ris/Grot 15%). Other profiles use their existing unit/group goals. Target uses actual revenue times each applicable dated unit margin goal, falling back to the existing group margin default. The goal is a revenue-based path, not a time-prorated annual budget or a forecast. No guessed goals are added. If any nonzero revenue lacks a goal, the overall goal badge says incomplete and the whole target path is hidden. Result percentage is null when cumulative revenue is not positive.

## Authorization
RPC hub_foreman_result_trend_v1 reuses private.hub_transport_leader_facts_v2. Owner previews and dated canonical-unit assignments remain identical. Sortergarden remains KST20 only, including shared units without exposing other cost centers. Authenticated EXECUTE is intentional; PUBLIC and anon are revoked, search_path is empty, auth/tenant/scope checks occur in the existing scope helper. Security advisor's authenticated SECURITY DEFINER notice is expected and covered by authorization tests. The page checks report generation and period match before rendering the trend.

## Verification
- Authenticated SQL checks: four profiles x YTD, imported-revenue cutoff, month, fiscal year and an empty future period; cumulative endpoints exactly match scorecard v4 revenue/cost/result/goal; date order and signed calculations validated.
- Supervisor own scope allowed, colleague impersonation and another tenant denied; missing auth and reversed periods denied; anon EXECUTE false.
- scripts/test-foreman-trend.mjs covers signed scales, missing goals, zero/one-day/empty data and no future extrapolation.
- Existing period helper tests retained.
- Run trend and period tests before the Next production build.
The area goal is tested to equal 20% of total revenue for Sortergarden only; other profiles and per-unit targets retain their goals.\n\nNo local execution environment was available in this turn. Validation uses the remote Vercel build, authenticated SQL and automated rendering checks; no signed-in browser screenshot check is claimed.
