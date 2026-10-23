# Project material refunds – KST 10

Read-only Hub report and CSV export in Interna körningar. Reuses published material-margin details and the transfer adapter's canonical identity-key, dated classification and approved-cost-scope knowledge. Resolves only the selected published source IDs, instead of recomputing the full ledger/transfer report. No source imports, KPI facts, transfer ledger, export status or bookkeeping is changed.

Scope: invoiced internal material, same published financial basis and cost-estimate rule as Overview; period/date/month selection is preserved. Unlike the older center-transfer totals (all order statuses), this proposal only covers invoiced material. Non-10 receiver rows and unallocated rows remain in a visible reconciliation.

Proposal = internal billed material minus calculated purchase cost. Signed credits and negative differences are retained. Transport and tipping are not refunded. Bundled transport rows stay visible but cannot have a pure material refund proposed until their selling price is split; their refund is null, not zero.

Canonical project IDs group identified projects. Unidentified source project references are grouped explicitly as provisional reference labels, not created as new Humla identities. Default receiving-KST rules are prominently flagged; project identity does not imply a verified historical KST. Names come from existing canonical project objects. Missing names remain missing.

September 2026: all internal material 508835.68; KST10 proposal covers 103 rows on 16 project references, billed507089.58, purchase393550.18, refund113539.40. One other-center row billed1746.10 is separately reconciled. Eight references lack canonical identity. All 103 KST10 rows currently use the adapter's default KST10 classification, so the proposal requires review before any posting.

Verification: summary reconciles to published margin report; project totals/row counts reconcile; date-only UI selection matches month selection; rollback credit test; unauthenticated RPC rejection; no ledger changes. Scoped source IDs, indexed canonical UUID lookup and custom planning keep the selected-month RPC within the authenticated 8-second statement timeout. Live UI shows all 16 project references and correct totals. CSV formatting tests cover UTF-8 BOM, formula escaping, negative values and decimal separator.

Navigation label KPI is renamed Enhetsuppföljning in dashboard, detail shell and control workspace, without changing routes or data.
