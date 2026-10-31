# September 2026 – historical import reconciliation

Read-only verification performed 2026-10-14 against Supabase project `vuurtaafxvevbhdzgttq`. No financial tables were mutated.

## Workify source exports
- 2026-09-01 through 2026-09-30, imported 2026-10-06
- 2026-09-01 through 2026-10-12, imported 2026-10-12

Rows scoped to occurred_on 2026-09-01..2026-09-30:

| Version | KST20 valid | KST30 valid | Non-valid amounts |
| --- | ---: | ---: | ---: |
| Earlier | 371,171.20 SEK | 6,924,854.02 SEK | 5,586.90 SEK |
| Later | 381,538.24 SEK | 7,254,979.68 SEK | 55,340.22 SEK |

Latest valid KST 20+30 total: 7,636,517.92 SEK. User's Workify control total: approximately 7,611,000 SEK; unverified difference 25,517.92 SEK.
Latest raw total including non-valid rows: 7,691,858.14 SEK. Do not omit non-valid economic amounts from a control register.

At *order number* level, compared across the two exports:
- 642 order numbers across both versions, 619 in both versions.
- 23 new order numbers in latest snapshot (302,239.16 SEK), none missing from latest.
- 26 existing order numbers changed totals; net increase 88,006.86 SEK.
- Content-hash / maximum-occurrence deduplication of both files yields **8,958,157.81 SEK** and is incorrect for snapshot-based orders. A later changed line is not additional revenue.

Examples of changed existing orders: 44718 +24,610 SEK; 44716 +24,075 SEK; 44715 +20,965 SEK; 44717 +19,250 SEK; 44283 -4,959 SEK.

## Release-blocking conclusions
1. Do not UNION/ADD historical snapshot imports to compute September revenue, even with content deduplication.
2. Determine a canonical final snapshot of each order (and stable line identifiers where available) from Workify, with correction/version and effective date. Missing stable identifiers must enter review, not be discarded or double-counted.
3. Show excluded/non-valid lines as **economic review amounts** until resolved; eligibility to allocate to a vehicle is distinct from inclusion in monetary control.
4. Next cost exports 71/72 and historic imports need equivalent source-specific reimport verification, plus separation of payroll costs from TransPA.
5. Verify exact Workify source filter behind the 7.611 mkr control total; do not force the system to match by arbitrary adjustments.
6. PR #43 targeted tests (9/9), TypeScript and production build passed. Repository-wide CI lint failed on main **and** PR, so this remains a release gate.
7. TransPA API adapter end-to-end, identity-key date validity and persisted corrected source lines are not yet certified.

## Safe verification SQL examples

```sql
-- Non-destructive snapshot comparison (order counts and changed amounts).
WITH x AS (
 SELECT
   CASE WHEN b.file_name LIKE '%10-12.xlsx' THEN 'latest' ELSE 'previous' END version,
   r.source_data->>'Ordernummer' order_number, r.amount, r.is_valid
 FROM public.kpi_import_rows r
 JOIN public.kpi_import_batches b ON b.id=r.batch_id
 WHERE r.tenant_id=:tenant_id
 AND r.data_kind='revenue'
 AND r.occurred_on BETWEEN '2026-09-01' AND '2026-09-30'
 AND b.file_name IN (
 'Workify_Elleholms_Maskin_AB_Orderexport_2026-09-01--2026-09-30 (1).xlsx',
 'Workify_Elleholms_Maskin_AB_Orderexport_2026-09-01--2026-10-12.xlsx'
 )
), orders AS (
 SELECT order_number,
 sum(amount) FILTER (WHERE version='latest') latest_amount,
 sum(amount) FILTER (WHERE version='previous') previous_amount
 FROM x GROUP BY order_number
)
SELECT count(*) FILTER (WHERE latest_amount IS NOT NULL AND previous_amount IS NOT NULL) shared_orders,
count(*) FILTER (WHERE previous_amount IS NULL) new_orders,
count(*) FILTER (WHERE latest_amount IS DISTINCT FROM previous_amount
 AND latest_amount IS NOT NULL AND previous_amount IS NOT NULL) changed_orders
FROM orders;
```

No deployment/merge should be described as certified until the end-to-end live API+database economic totals match a reconciled control report.
