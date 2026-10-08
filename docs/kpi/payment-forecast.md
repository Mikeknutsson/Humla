# Avdelningens betalningsprognos – första version

## Payroll projection (2026-10-08)

Automatic mode adds a separate TransPA gross-pay projection to outgoing forecast/total and net once. Previous work month is paid on calendar day 25 of the following month, with no unverified holiday adjustment. Existing allocated Hub TransPA facts are aggregated by month/KST; their default employer-cost load is removed using the settings that match the snapshot. No vehicle/person cost is allocated a second time, no new identity guesses, no PO/pension/social-cost cash uplift, no net-pay or withholding-tax inference. Salary settings changed after the prepared snapshot block the payroll calculation until Hub sync. Both source RPCs must return the same snapshot timestamp.

Closed work months use observed time-based gross-pay estimates. Current/future work months use the prior-year work month times a separate completed-fiscal-month payroll trend when sufficiently comparable. Sparse history falls back to the latest sufficiently reported closed month (at most two months old), explicitly labeled. A month needs reports on at least 60% of its weekday count and at least 25% of the latest sufficiently reported month's report volume; these are conservative availability checks, not audited payroll completeness. Duplicate monthly source keys are rejected. Missing payroll in a payment week makes that department's outgoing total/net incomplete; other weeks have zero scheduled payroll, not a repeated monthly charge. Manual CSV mode is unchanged and does not add TransPA payroll.

Live check: KST 30 September 2026 gross-pay estimate 935,204.99 SEK, scheduled October 25. November 25 is currently a September-based fallback for October work because comparable early historical imports are sparse. KST 20 has no mapped TransPA payroll facts, so its payroll remains missing. Unclassified/other-KST TransPA amounts are disclosed and excluded, never assigned to Transport or Sortergården by guess. User confirmed wages are not present in NeXT; if wages are later imported there, reconciliation is required to avoid double counting. The figure is not verified actual payroll, bank cash, OB/leave completeness or net pay.

Confirmed Stena classification (2026-10-08): Workify label `Elleholms Maskin (STENA)` is external Stena revenue, not an internal transfer. The Hub payment source and invoice-lead-time classification use the same private customer policy; ordinary Elleholms Maskin AB remains internal. Forecast headline amounts and CSV show registered external amounts plus remaining forecast, so Stena's already registered monthly settlement is included once and matches the basis of net. Registered amounts below are a breakdown, not an extra amount to add.

## Current default: Workify and NeXT outcome forecast

No upload required: Dashboard calls the permission-guarded `hub_payment_outcome_source_v1` RPC. Revenue comes from the active prepared Workify snapshot; cost comes from valid NeXT import rows before vehicle-result/Piusi/material filters. Date-versioned project classification is used; conflicting cost-center classifications remain unclassified. Source rows are aggregated before leaving the database. Existing records and KPI reports are not modified.

Customer terms: 30 calendar days from invoice date normally; 45 for Linnestofta Maskin AB and Thomas Håkansson Entreprenad (including explicit AB aliases). Stena names beginning with Stena use 45 calendar days after the last delivery-month day, regardless of invoice date; deliveries in the same month land on the same assumed settlement date. Missing invoice dates use delivery date as an explicit assumption. No bank-day or unverified payment-status inference. Elleholms Maskin AB remains internal and separately shown. User-confirmed Elleholms Maskin (STENA) is external Stena revenue, included once in external figures and using Stena month-end terms. Original customer names and source IDs are retained.

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

Internal revenue and costs are shown in regular-weight forecast rows directly under the three summary rows, per department and total. They use their own prior-year weekly baseline and their own current-year trend, with the same registered-remainder safeguard as external forecasts. Internal history and trend never mix with external amounts and net. Internal totals stay incomplete if a department lacks comparable internal history; missing is not zero. Automatic internal baseline coverage is evaluated on assumed payment dates rather than the external customer/Stena lag envelope. Manual mode uses declared historical coverage and the separate internal 13-week trend.
