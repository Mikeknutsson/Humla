# Min körning

Route `/chauffor`, owner account links `/chauffor/admin`. Workers land here from the normal KPI login. Existing owner preview selects a canonical Person, while other users can only read the Person explicitly bound to their authenticated account. No invitations or accounts are created automatically.

Canonical account links are owner-confirmed, tenant-scoped, versioned in `private.hub_driver_account_links`, and revocable. One active account per canonical person. Only active worker accounts may be bound. Historical time references resolve inside the Hub adapter through unambiguous confidence-1 canonical `transpa_employee_id` identities; names are never used as authorization.

The narrow RPC returns qualitative statuses only, not money, exact hours, orders, source rows, employee IDs, or colleagues. Reporting feedback describes only imported records (approved/submitted); it cannot detect missing days without a work schedule. Vehicle-link feedback describes time with a single annotated vehicle and does not claim that the employee drove it. Four qualitative weekly bands and a comparison to the preceding equal-duration period use the same scoped time data. Periods are Stockholm today, current week/month or latest 28 days.

Thresholds: vehicle-time share >=90% good, >=50% partial, otherwise attention; zero records unknown. Weekly bands split at 50%, 75%, 90%. Trend changes only beyond 5 percentage points; no personal targets are invented.

Economic and fuel assessment are explicitly **not activated**. The existing driver matching contract says TransPA alone never proves vehicle driver; verified driving evidence is currently absent. Tanked fuel without matched distance/operating conditions is not consumption. No economic feedback is attributed from these proxies.

Apply `docs/sql/driver-self-service.sql`. Privileged implementations stay in private, with authenticated invoker wrappers and explicit active-member/owner checks. Links have RLS and no direct authenticated grants. Authorization verification: `supabase/tests/driver_self_service.sql` uses an existing member transactionally, rolls all fixtures back, and checks self-scope, cross-tenant denial, directory denial, bind/unbind, no financial fields and no broad KPI permission. UI period tests: `node scripts/test-driver-self.mjs`.

Validation: production Next build and TypeScript; live authenticated-role database checks; 390px visual check of the actual server-rendered page with synthetic data. Full signed-in browser verification requires an existing user session; no production auth bypass is provided.
