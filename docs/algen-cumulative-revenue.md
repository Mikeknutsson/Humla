# Rivning Kv Älgen: cumulative invoiced revenue

Mike approved 485798 SEK excluding VAT as the whole-project invoiced total on 2026-10-15, based on IMG_2058.png (Library libfile_458c50fbedd88191bbb4d5af0280f4cf), also cropped in IMG_2057.jpeg. The screenshot has no invoice dates. It is not a September-only amount.

Canonical project d0e501bc-b300-479e-8941-e9227b635113 resolves uniquely through confirmed NEXT project identity12716. The immutable evidence row is in private.hub_project_revenue_statements, with observed date, source reference, approval and unique source key. Existing imported NEXT revenue is150000 from August2026, leaving335798 not yet date-distributed. Do not add485798 on top of150000 or invent a transaction date.

Projectuppföljning shows the cumulative statement separately above the period report when the project is selected. Its value does not change with month filters and does not alter period totals, cash-flow or financial facts. Later imported invoices reduce the undistributed difference; the cumulative total is never summed again. No profit is computed from costs with a potentially different scope.

Validation: unique canonical resolution; idempotent evidence insertion; rollback test for original revenue and later full invoice coverage; anonymous access rejection; deny-all RLS on evidence table; authenticated tenant-scoped read RPC; production build and selected-project UI verification.
