# Invoice lead time

Hub owns the calculation. The nightly prepared projection retains Workify's
order number, article date and actual invoice date (`Fakturadatum`, falling back
to the export's `Fakturerad` date). The financial rule treating registered revenue
as invoiced does not change these source dates or feed this KPI.

The KPI is an unweighted mean of calendar days from order completion to invoice date,
once per order. `Slutdatum`, then Workify `PlaneradKlart`, provides the completion
date. Only a missing end date falls back to the last article date. Invalid end
dates, conflicting end dates and completion before the last article are excluded.
Orders are selected through article rows in the exact active report selection.
The whole prepared order supplies its dates, including rows outside selected
months or units, so a filter cannot move completion backwards.
Duplicate article lines and the derived material/transport split do not add weight.
Uninvoiced lines are excluded. Negative, invalid and conflicting invoice dates are
excluded and counted as date anomalies. No clamping to zero or absolute values.
From 2026-10-07, zero-day invoices remain in the detail table but are excluded
from the average. `averaged_orders` is the positive external-order denominator;
`zero_orders` reports the excluded zero-day count. An all-zero selection
returns a null average, never an invented zero.

The overview card links to a paginated Dashboard report, retaining fiscal months,
cost centres, business groups and unit filters. The public RPC is an invoker and
the private implementation requires authenticated `kpi.read` for the tenant.

Rollback tests cover duplicate lines, multiple days on one order, zero-day billing,
uninvoiced lines, negative dates, conflicting dates, invalid calendar dates and
month selection. Test rows never persist. The build and real-data production view
must also pass.

LMT31J audit, September 2026: NEXT costs remain on canonical unit LMT31J including
the cassette trailer RLW15A (projects 9030/969). 175,821.02 SEK in gravel purchases
moved to the material unit as requested. User confirmed Erik Ivarsson is an
external invoicing driver, not a TransPA payroll source. His six imported NEXT
invoices (April–August, 317,572 SEK) already map to LMT31J/personnel. No September
invoice is imported; no monthly estimate is inserted.

Piusi has 21 September tankings, 3,703.94 litres and 50,356.56 SEK of provisional
API-priced fuel for LMT31J. The common Hub prepared ledger now includes accepted
Piusi costs and preserves NEXT 5360 tank purchases as zero-impact reconciliation
rows, with their booked amount in source metadata. This feeds the Overview, KPI,
monthly series, units, comparison, export and drilldown from one generation.
LMT31J September total cost becomes 111,701.74 SEK, still without a September
chauffeur invoice. No source rows or account rules are changed. The month drilldown
now reads the same prepared generation rather than rebuilding live classifications.

From 2026-10-07, customer names containing Elleholms Maskin (case insensitive,
including AB/STENA/service labels) identify internal transfers. Hub excludes them
from the main positive-day average and returns a separate internal average and
denominator. Both types remain in detail, with a Hub-provided is_internal flag.
Other Elleholms customer names remain in the external selection.

The Overview includes separate external and Elleholms Maskin invoice-time cards.
Their links set `invoice_customer=external|internal`; Hub filters the paginated
rows and returns `row_count` for that type. Summary columns retain both averages.
Legacy order-day fields remain as compatibility aliases for older consumers;
their values now represent orders, never order-day weighting. Both cards use the
same prepared generation and daily report cache. Cache v6 invalidates old formulas.
`supabase/tests/invoice_order_completion.sql` exercises weekly and cross-month
orders, duplicate rows, fallback, exclusions and internal drilldown under rollback.
