-- Humla KPI: effective-dated margin targets per economic unit.
-- Prepared separately from the Hub ingestion work; not deployed by this migration file.
create table if not exists public.hub_kpi_unit_margin_targets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  unit_key text not null check (length(trim(unit_key)) > 0),
  valid_from date not null,
  valid_to date,
  target_margin_percent numeric(7,3) not null check (target_margin_percent between -100 and 100),
  note text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hub_kpi_unit_margin_targets_dates check (valid_to is null or valid_to >= valid_from),
  constraint hub_kpi_unit_margin_targets_unique_start unique (tenant_id,unit_key,valid_from)
);
create index if not exists hub_kpi_unit_margin_targets_lookup
  on public.hub_kpi_unit_margin_targets (tenant_id,unit_key,valid_from desc);
create extension if not exists btree_gist;
alter table public.hub_kpi_unit_margin_targets
  add constraint hub_kpi_unit_margin_targets_no_overlap
  exclude using gist (
    tenant_id with =,
    unit_key with =,
    daterange(valid_from,coalesce(valid_to + 1,'infinity'::date),'[)') with &&
  );
alter table public.hub_kpi_unit_margin_targets enable row level security;
create policy hub_kpi_unit_margin_targets_read on public.hub_kpi_unit_margin_targets
  for select to authenticated using (public.hub_has_permission(tenant_id,'kpi.view'));
create policy hub_kpi_unit_margin_targets_write on public.hub_kpi_unit_margin_targets
  for insert to authenticated with check (public.hub_has_permission(tenant_id,'kpi.manage'));
create policy hub_kpi_unit_margin_targets_edit on public.hub_kpi_unit_margin_targets
  for update to authenticated using (public.hub_has_permission(tenant_id,'kpi.manage'))
  with check (public.hub_has_permission(tenant_id,'kpi.manage'));
create policy hub_kpi_unit_margin_targets_delete on public.hub_kpi_unit_margin_targets
  for delete to authenticated using (public.hub_has_permission(tenant_id,'kpi.manage'));
-- Financial KPI query contract:
-- target_result = eligible_revenue * target_margin_percent / 100
-- deviation_amount = actual_result - target_result
-- deviation_percentage_points = actual_margin_percent - target_margin_percent
-- Aggregate target margin = sum(target_result) / sum(eligible_revenue) * 100.
-- For a period spanning target changes, split revenue into effective-dated slices.
-- Never sum the same transaction in both area and vehicle perspectives.
