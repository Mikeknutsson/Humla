-- Stability hardening verified 2026-09-28.
-- Principle: authenticated users receive only privileges backed by explicit RLS policies.
do $$ declare r record; begin
  for r in
    select table_name from information_schema.tables t
    where table_schema='public' and table_type='BASE TABLE'
      and exists(select 1 from pg_policies p where p.schemaname='public' and p.tablename=t.table_name)
  loop
    execute format(
      'revoke insert, update, delete, truncate, references, trigger on table public.%I from authenticated',
      r.table_name
    );
  end loop;
end $$;

-- These two client workflows have explicit tenant-scoped UPDATE policies.
grant update on table public.hub_machine_work_sessions, public.hub_review_queue to authenticated;

-- The runtime checkpoint also asserts that broad authenticated mutation grants do not return.
-- hub_checkpoint_v1 is backend-only (service_role) and currently verifies:
-- RLS enabled, anon RPC exposure, anon policyless-table exposure,
-- broad authenticated mutation grants, dead letters and failed Physical Activity jobs.
