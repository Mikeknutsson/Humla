# Humla database migrations

All new production database changes must be represented here after they have been verified against the Humla Hub database.

Rules:
1. Make and verify the change in Supabase.
2. Run the database checkpoint and Supabase advisors.
3. Add an idempotent migration representing the verified change.
4. Never expose backend-only tables or functions to anon.
5. Prefer SECURITY INVOKER. Backend functions are service_role only unless an authenticated client explicitly needs them.

The existing database predates this folder. A complete baseline export still needs to be generated from the live schema before the database can be rebuilt solely from Git.
