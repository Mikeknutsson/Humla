# Humla stability policy

Humla is developed with continuous stability as a hard requirement.

## Before and after structural changes
- Verify production build.
- Run TypeScript and lint checks.
- Run Supabase security/performance advisors for database changes.
- Run `hub_checkpoint_v1()` after backend changes.
- Keep RLS enabled on every exposed public table.
- No `hub_*` function is executable by anon.
- SECURITY DEFINER functions must never be exposed to anon.
- Backend maintenance/orchestration functions are service_role only.
- Preserve source data and make reconstruction changes idempotent where possible.

## Current checkpoint invariants
A healthy Hub checkpoint requires:
- zero public tables with RLS disabled;
- zero anon-executable `hub_*` functions;
- zero anon-readable policyless backend tables;
- zero dead-letter records;
- zero failed Physical Activity jobs.

## Database reproducibility
The current live database predates migration tracking in this repository. New changes are migration-tracked from 2026-09-28 onward. A full schema baseline is still required before claiming that the database can be recreated exclusively from Git.
