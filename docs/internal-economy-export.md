# Accounting PDF for internal transfers

The export follows the supplied Elleholms landscape template with a project
summary, detailed order rows, original debited amounts, price adjustments,
transfer amounts and material price evidence. It is available separately for
10 -> 30 Transport and 10 -> 20 Sortergården in Internal transfers.

Final approved valuation:

- Material: existing Hub purchase/self-cost evidence, including approved
  provisional estimates. No additional discount on this cost.
- Tipping/deposit fees: 100% of debited line amount.
- Transport: 100% of debited line amount, including a published transport
  component split from a material-with-transport article.
- Credits preserve their sign. Round each transfer component to two decimals.

Hub owns selection, duplicate reconciliation, valuation and totals. PDF code
formats its report and filters its already calculated center summaries. A
download does not book, change export status or alter KPI revenue. Previously
exported/preliminary rows remain visible with their evidence status. Conflicting
source rows and unallocated centers stay in the reconciliation, not silently
valued. Missing cost is null and explicitly incomplete rather than zero.

The legacy R0-1 Matjord article is classified as transport. The accounting
projection recognizes its material name and shows missing self cost; no soil
production cost is inferred from a gravel price list or from its selling price.
Supplying an approved soil self cost remains necessary for that part of KST 20.

Applied functions are additive to the existing transfer ledger. Tests cover
full transport and tipping prices, negative credits, material self cost,
bundle conservation, missing prices, Matjord and anonymous denial. The pure
engine and tenant-scoped live report are verified before publication. The
supplied source PDF is not stored in the public repository; only its wordmark
is reused as the document's branding asset.
