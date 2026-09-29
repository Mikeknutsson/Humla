# TransPA evidence bridge

Existing connection and Edge Function transpa-sync reused, version 9. Official live OpenAPI version 0.1.140 checked at https://api.mytranspa.com/doc/openapi/openapi.yaml on 2026-09-29.

Fixed timeReports requests to supply required from/to (maximum 31 days). Salary configuration and employee contracts use documented per-employee paths, rather than nonexistent collection routes. Existing default entity imports unchanged. Optional page/employee bounds support controlled testing. Worker authentication and Vault remain server-side; no tokens or credentials output. Upstream errors no longer include raw response bodies. Upsert failures are counted as errors. Page bounds indicate incomplete results rather than claiming completion.

Live August 2026 time report sync completed: 414 records, 24 employees, 3787.05 adjusted work hours, 3760.30 hours in approved reports, 3 unapproved reports, 24 distinct source vehicle references. Repeated IDs upsert rather than duplicate. Two salary configuration requests succeeded but only supply vacationWagePerDay. No actual salary export records retrieved. No salary subscription or export-status mutation performed.

New admin-only KPI TransPA-underlag view reads an aggregate from Hub via a private guarded function. No raw HR records exposed and no write to financial KPI/imports. Permanent person mapping is 0/27; do not infer paid/billable hours or daily wage cost from tachograph or work time. Salary resource requires an ID, normally obtained via salary export webhook; existing payroll export behavior must be understood before activation.

Validation: live token/API success; completed sync with 414 upserts; authenticated aggregate query; unauthorized actor rejected. Next.js build excludes the Deno Edge Function directory. In-app authenticated browser verification remains unavailable.
