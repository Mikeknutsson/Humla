# Avdelningens betalningsprognos – första version

Route: `/kpi/betalningsprognos`. Whole-department scope: cost centers 30 Transport, 20 Sortergården and 40 Verkstad, individually and summed. No inherited KPI vehicle/project filters. Both page and API require active tenant membership and `kpi.manage`.

## Calculation owned by Hub

`src/lib/hub/payment-forecast.ts`: previous year's comparable weekly outcome (364-day alignment) multiplied by the ratio of the latest 13 completed weeks to the same weeks last year, separately for each department and payment direction. ISO weeks +4 through +7 from the current week, including year rollover. With booked outcome, the historical baseline is shifted by explicitly selected customer/supplier payment lag; actual-payment history requires no lag. Input amounts must already be cash amounts including VAT. Do not infer VAT from book costs.

Open residual amounts in customer/supplier ledgers use due dates. Forecast remainder is max(0, adjusted historical expectation minus known ledger); never add the full expectation on top of known invoices. Negative amounts are credits. Missing coverage, or a non-positive prior comparison denominator, yields null rather than a misleading zero. Complete explicit history dates attest days with no transactions. Internal transfers excluded. Missing/other cost centers and overdue balances are separately listed, excluded from target-week totals.

## Input contract

Normalized semicolon CSV: `id;kst;typ;datum;belopp;intern`. Direction `in/out`, internal `ja/nej`, ISO date, decimal comma or dot, unique source-row ID. For split invoices, IDs must identify separate allocation lines. Reject repeated IDs, missing amounts, invalid dates and malformed quotes. Import replaces the relevant complete dataset, not appends. Adapter does not persist identity guesses. No database schema changes.

## Delivery and limitations

Internal runs/transfers are separately shown per cost center and source dataset and exported as individual rows. They are excluded from known external payments, prior-year baseline and current-year trend. Only the internal accounting transfer is flagged; actual external supplier/payroll/fuel costs of performing an internal run remain external costs. Import adapter requires explicit `intern=ja/nej`; automatic classification from live Workify/ledger sources is not implemented in this first version.

Excel-compatible CSV contains all four views, report date, provenance filenames, assumptions, overdue and unassigned rows. Not an XLSX workbook with separate tabs. No automatic reskontra ingestion, stored weekly snapshots or unattended delivery yet. Uploaded source rows are request-scoped, not persisted. No bank balance, payroll/tax/loan completeness assertion, or automatic VAT calculation. Historical period is user-attested; not independently verified against accounting controls. API is origin-checked and not cacheable.

Tests: `node scripts/test-payment-forecast.cjs`; TypeScript: `npx tsc --noEmit`. Public release requires verified access to existing Vercel Humla project; do not register a replacement project or publish unrelated dirty changes. Browser/authenticated integration flow and actual data remain to be verified.
