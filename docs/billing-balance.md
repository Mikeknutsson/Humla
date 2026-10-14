# Overview billing balance

The Overview loads a compact, read-only Hub metric separately from the financial
report so an unavailable widget cannot block the page. It follows the fiscal
month selection and cost-centre/group/unit/vehicle/project filters. Cache keys
include tenant, reader, report generation, correction revision and scope.

Workify revenue uses its invoice date and an Invoiced status. The published fact
amount is used, so material/haulage components sum to the original source amount.
Supplier costs use their NEXT booking date. Internal counterparties and internal
time/allocation vouchers, salary account 7010, own-tank consumption and non-NEXT
derived costs are excluded. Unidentified counterparties and missing invoice dates
are exposed separately; they never silently count as verified external invoicing.

The net is invoiced revenue less eligible registered costs, excluding VAT.
Weekly bars show that week's net; the expandable table also shows its running
balance over the selected months. ISO weeks crossing period boundaries include
only selected dates. Credits retain their signs. No data yields a missing value,
not a green zero. This is a billing lead indicator, not a payment/bank forecast.

Internal transfers are deliberately excluded in this version. Any later option
belongs in the Hub calculation and must keep its cache identity and displayed
scope distinct. No financial facts or mappings are modified by this feature.
