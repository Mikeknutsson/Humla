# Avdelningens betalningsprognos – första version

## Current default: Workify and NeXT outcome forecast

No upload required: Dashboard calls the permission-guarded `hub_payment_outcome_source_v1` RPC. Revenue comes from the active prepared Workify snapshot; cost comes from valid NeXT import rows before vehicle-result/Piusi/material filters. Date-versioned project classification is used; conflicting cost-center classifications remain unclassified. Source rows are aggregated before leaving the database. Existing records and KPI reports are not modified.

Customer terms: 30 calendar days from invoice date normally; 45 for Linnestofta Maskin AB and Thomas Håkansson Entreprenad (including explicit AB aliases). Stena names beginning with Stena use 45 calendar days after the last delivery-month day, regardless of invoice date; deliveries in the same month land on the same assumed settlement date. Missing invoice dates use delivery date as an explicit assumption. No bank-day or unverified payment-status inference. Internal Elleholms customers, including Elleholms Maskin (STENA), remain excluded and separately shown; external Stena settlements need external source evidence.

`payment-outcome-forecast.ts` computes trends from completed months in the current September–August fiscal year, compared with identical dates last year, by cost center and direction. Prior comparable payment weeks are aligned 364 days back; existing registered outcomes with estimated payment dates in the target week reduce the forecast remainder. Department-specific source date coverage is checked; missing/sparse comparison coverage produces null, including totals when any department is incomplete. Coverage is an availability check, not an audited completeness certification. No automated VAT uplift: outcomes are ex VAT and the report explicitly distinguishes estimated payments from real reskontra. Supplier payment lag is a separately editable assumption, initially 30 days.

Validated on 8,992 aggregated live-source rows as of 2026-10-08. Cost-center 20 cost coverage ends 2026-09-11, cost-center 40 cost coverage ends 2026-09-04, and 40 lacks external Workify revenue. These remain incomplete, rather than zero or an invented trend. Tests cover terms, monthly Stena aggregation, leap/year boundaries, registered remainder, internal exclusions and missing departments.

The following describes the optional manual CSV mode, retained as a fallback.

Route: `/kpi/betalningsprognos`. Whole-department scope: cost centers 30 Transport, 20 Sortergården only, individually and summed. No inherited KPI vehicle/project filters. Both page and API require active tenant membership and `kpi.manage`.

## Calculation owned by Hub

`src/lib/hub/payment-forecast.ts`: previous year's comparable weekly outcome (364-day alignment) multiplied by the ratio of the latest 13 completed weeks to the same weeks last year, separately for each department and payment direction. ISO weeks +4 through +7 from the current week, including year rollover. With booked outcome, the historical baseline is shifted by explicitly selected customer/supplier payment lag; actual-payment history requires no lag. Input amounts must already be cash amounts including VAT. Do not infer VAT from book costs.

Open residual amounts in customer/supplier ledgers use due dates. Forecast remainder is max(0, adjusted historical expectation minus known ledger); never add the full expectation on top of known invoices. Negative amounts are credits. Missing coverage, or a non-positive prior comparison denominator, yields null rather than a misleading zero. Complete explicit history dates attest days with no transactions. Internal transfers excluded. Missing/other cost centers and overdue balances are separately listed, excluded from target-week totals.

## Input contract

Normalized semicolon CSV: `id;kst;typ;datum;belopp;intern`. Direction `in/out`, internal `ja/nej`, ISO date, decimal comma or dot, unique source-row ID. For split invoices, IDs must identify separate allocation lines. Reject repeated IDs, missing amounts, invalid dates and malformed quotes. Import replaces the relevant complete dataset, not appends. Adapter does not persist identity guesses. No database schema changes.

## Delivery and limitations

Internal runs/transfers are separately shown per cost center and source dataset and exported as individual rows. They are excluded from known external payments, prior-year baseline and current-year trend. Only the internal accounting transfer is flagged; actual external supplier/payroll/fuel costs of performing an internal run remain external costs. Import adapter requires explicit `intern=ja/nej`; automatic classification from live Workify/ledger sources is not implemented in this first version.

Excel-compatible CSV contains all four views, report date, provenance filenames, assumptions, overdue and unassigned rows. Not an XLSX workbook with separate tabs. No automatic reskontra ingestion, stored weekly snapshots or unattended delivery yet. Uploaded source rows are request-scoped, not persisted. No bank balance, payroll/tax/loan completeness assertion, or automatic VAT calculation. Historical period is user-attested; not independently verified against accounting controls. API is origin-checked and not cacheable.

Tests: `node scripts/test-payment-forecast.cjs`; TypeScript: `npx tsc --noEmit`. Public release requires verified access to existing Vercel Humla project; do not register a replacement project or publish unrelated dirty changes. Browser/authenticated integration flow and actual data remain to be verified.

## Period navigation and department scope

Payment forecast includes only 30 Transport and 20 Sortergården. KST 40 is excluded from totals and remains outside-scope source data. The initial window is ISO weeks +4 through +7. Previous/next move the four-week window by four weeks without changing the report date, source cutoff or trend period. The API validates the week offset within ±104 weeks. Summary rows appear first (customer forecast, cost forecast, net); registered-source rows follow in regular weight. CSV columns use the same order.

Internal revenue and costs are shown in regular-weight rows directly under the three summary rows, per department and total. They are registered source amounts assigned to the displayed payment weeks (estimated dates in automatic mode); they are excluded from external forecasts, trend and net.
