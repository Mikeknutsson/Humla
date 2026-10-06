# Invoice lead time

Hub owns the calculation. The nightly prepared projection retains Workify's
order number, article date and actual invoice date (`Fakturadatum`, falling back
to the export's `Fakturerad` date). The financial rule treating registered revenue
as invoiced does not change these source dates or feed this KPI.

The KPI is an unweighted mean of calendar days from article date to invoice date,
once per order and performed day within the exact active report selection.
Duplicate article lines and the derived material/transport split do not add weight.
Uninvoiced lines are excluded. Negative, invalid and conflicting invoice dates are
excluded and counted as date anomalies. No clamping to zero or absolute values.

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
