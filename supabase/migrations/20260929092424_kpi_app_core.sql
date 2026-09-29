-- Humla KPI is a separate application domain. Humla Hub remains the integration
-- and canonical-data layer; these tables own KPI configuration and manual imports.

insert into public.hub_permissions (code, name, description)
values
  ('kpi.read', 'Visa Humla KPI', 'Visa nyckeltal, importer och detaljunderlag i Humla KPI.'),
  ('kpi.manage', 'Hantera Humla KPI', 'Importera underlag och administrera mål och KPI-regler.')
on conflict (code) do update
set name = excluded.name,
    description = excluded.description;

insert into public.hub_role_permissions (role, permission_code)
values
  ('owner', 'kpi.read'), ('owner', 'kpi.manage'),
  ('admin', 'kpi.read'), ('admin', 'kpi.manage'),
  ('management', 'kpi.read'),
  ('economy', 'kpi.read'), ('economy', 'kpi.manage'),
  ('manager', 'kpi.read')
on conflict (role, permission_code) do nothing;

create table if not exists public.kpi_settings (
  tenant_id uuid primary key references public.hub_tenants(id) on delete cascade,
  currency text not null default 'SEK',
  timezone text not null default 'Europe/Stockholm',
  financial_year_start_month smallint not null default 9 check (financial_year_start_month between 1 and 12),
  financial_year_start_day smallint not null default 1 check (financial_year_start_day between 1 and 28),
  vehicle_capacity_hours_per_day numeric(8,2) not null default 8 check (vehicle_capacity_hours_per_day > 0),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.kpi_targets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.hub_tenants(id) on delete cascade,
  kpi_code text not null check (kpi_code in ('revenue','result','revenue_per_vehicle','vehicle_utilization','diesel_share','driver_billability')),
  target_value numeric not null,
  warning_value numeric,
  valid_from date not null,
  valid_to date,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (valid_to is null or valid_to >= valid_from),
  unique (tenant_id, kpi_code, valid_from)
);

create table if not exists public.kpi_import_batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.hub_tenants(id) on delete cascade,
  source_type text not null check (source_type in ('manual_excel','manual_pdf','hub_api')),
  data_kind text not null check (data_kind in ('revenue','cost','fuel','vehicle_activity','driver_time')),
  file_name text,
  file_type text,
  file_size bigint check (file_size is null or file_size >= 0),
  file_hash text,
  storage_path text,
  status text not null default 'processing' check (status in ('processing','completed','needs_review','failed')),
  row_count integer not null default 0 check (row_count >= 0),
  valid_row_count integer not null default 0 check (valid_row_count >= 0),
  invalid_row_count integer not null default 0 check (invalid_row_count >= 0),
  period_start date,
  period_end date,
  column_mapping jsonb not null default '{}'::jsonb,
  provenance jsonb not null default '{}'::jsonb,
  error_summary jsonb not null default '[]'::jsonb,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check (period_end is null or period_start is null or period_end >= period_start)
);

create unique index if not exists kpi_import_batches_file_dedupe
on public.kpi_import_batches (tenant_id, data_kind, file_hash)
where file_hash is not null and status <> 'failed';

create index if not exists kpi_import_batches_tenant_created_idx
on public.kpi_import_batches (tenant_id, created_at desc);

create table if not exists public.kpi_import_rows (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.hub_tenants(id) on delete cascade,
  batch_id uuid not null references public.kpi_import_batches(id) on delete cascade,
  row_number integer not null check (row_number > 0),
  data_kind text not null check (data_kind in ('revenue','cost','fuel','vehicle_activity','driver_time')),
  occurred_on date,
  vehicle_object_id uuid references public.hub_objects(id),
  vehicle_registration text,
  employee_object_id uuid references public.hub_objects(id),
  employee_number text,
  project_reference text,
  cost_center text,
  account text,
  description text,
  quantity numeric,
  amount numeric,
  currency text not null default 'SEK',
  available_hours numeric check (available_hours is null or available_hours >= 0),
  occupied_hours numeric check (occupied_hours is null or occupied_hours >= 0),
  paid_hours numeric check (paid_hours is null or paid_hours >= 0),
  billable_hours numeric check (billable_hours is null or billable_hours >= 0),
  is_valid boolean not null default true,
  validation_errors jsonb not null default '[]'::jsonb,
  source_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (batch_id, row_number)
);

create index if not exists kpi_import_rows_period_idx
on public.kpi_import_rows (tenant_id, occurred_on, data_kind);

create index if not exists kpi_import_rows_vehicle_idx
on public.kpi_import_rows (tenant_id, vehicle_registration, occurred_on);

create index if not exists kpi_import_rows_employee_idx
on public.kpi_import_rows (tenant_id, employee_number, occurred_on);

create index if not exists kpi_import_batches_created_by_idx
on public.kpi_import_batches (created_by);

create index if not exists kpi_import_rows_vehicle_object_id_idx
on public.kpi_import_rows (vehicle_object_id);

create index if not exists kpi_import_rows_employee_object_id_idx
on public.kpi_import_rows (employee_object_id);

create index if not exists kpi_settings_updated_by_idx
on public.kpi_settings (updated_by);

create index if not exists kpi_targets_created_by_idx
on public.kpi_targets (created_by);

alter table public.kpi_settings enable row level security;
alter table public.kpi_targets enable row level security;
alter table public.kpi_import_batches enable row level security;
alter table public.kpi_import_rows enable row level security;

revoke all on public.kpi_settings, public.kpi_targets, public.kpi_import_batches, public.kpi_import_rows from anon;
grant select, insert, update, delete on public.kpi_settings, public.kpi_targets, public.kpi_import_batches, public.kpi_import_rows to authenticated;

create policy kpi_settings_read on public.kpi_settings
for select to authenticated using (public.hub_has_permission(tenant_id, 'kpi.read'));
create policy kpi_settings_insert on public.kpi_settings
for insert to authenticated
with check (public.hub_has_permission(tenant_id, 'kpi.manage'));
create policy kpi_settings_update on public.kpi_settings
for update to authenticated
using (public.hub_has_permission(tenant_id, 'kpi.manage'))
with check (public.hub_has_permission(tenant_id, 'kpi.manage'));
create policy kpi_settings_delete on public.kpi_settings
for delete to authenticated using (public.hub_has_permission(tenant_id, 'kpi.manage'));

create policy kpi_targets_read on public.kpi_targets
for select to authenticated using (public.hub_has_permission(tenant_id, 'kpi.read'));
create policy kpi_targets_insert on public.kpi_targets
for insert to authenticated
with check (public.hub_has_permission(tenant_id, 'kpi.manage') and created_by = (select auth.uid()));
create policy kpi_targets_update on public.kpi_targets
for update to authenticated
using (public.hub_has_permission(tenant_id, 'kpi.manage'))
with check (public.hub_has_permission(tenant_id, 'kpi.manage') and created_by = (select auth.uid()));
create policy kpi_targets_delete on public.kpi_targets
for delete to authenticated using (public.hub_has_permission(tenant_id, 'kpi.manage'));

create policy kpi_import_batches_read on public.kpi_import_batches
for select to authenticated using (public.hub_has_permission(tenant_id, 'kpi.read'));
create policy kpi_import_batches_insert on public.kpi_import_batches
for insert to authenticated
with check (public.hub_has_permission(tenant_id, 'kpi.manage') and created_by = (select auth.uid()));
create policy kpi_import_batches_update on public.kpi_import_batches
for update to authenticated
using (public.hub_has_permission(tenant_id, 'kpi.manage'))
with check (public.hub_has_permission(tenant_id, 'kpi.manage') and created_by = (select auth.uid()));
create policy kpi_import_batches_delete on public.kpi_import_batches
for delete to authenticated using (public.hub_has_permission(tenant_id, 'kpi.manage'));

create policy kpi_import_rows_read on public.kpi_import_rows
for select to authenticated using (public.hub_has_permission(tenant_id, 'kpi.read'));
create policy kpi_import_rows_insert on public.kpi_import_rows
for insert to authenticated
with check (public.hub_has_permission(tenant_id, 'kpi.manage'));
create policy kpi_import_rows_update on public.kpi_import_rows
for update to authenticated
using (public.hub_has_permission(tenant_id, 'kpi.manage'))
with check (public.hub_has_permission(tenant_id, 'kpi.manage'));
create policy kpi_import_rows_delete on public.kpi_import_rows
for delete to authenticated using (public.hub_has_permission(tenant_id, 'kpi.manage'));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'kpi-imports',
  'kpi-imports',
  false,
  20971520,
  array[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel',
    'text/csv'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy kpi_import_files_read on storage.objects
for select to authenticated
using (
  bucket_id = 'kpi-imports'
  and public.hub_has_permission(((storage.foldername(name))[1])::uuid, 'kpi.read')
);

create policy kpi_import_files_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'kpi-imports'
  and public.hub_has_permission(((storage.foldername(name))[1])::uuid, 'kpi.manage')
);

create policy kpi_import_files_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'kpi-imports'
  and public.hub_has_permission(((storage.foldername(name))[1])::uuid, 'kpi.manage')
);

insert into public.kpi_settings (tenant_id, updated_by)
select tenant_id, user_id
from public.hub_tenant_members
where status = 'active' and role = 'owner'
on conflict (tenant_id) do nothing;

create or replace function public.kpi_transport_dashboard(
  p_tenant_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
with scoped as (
  select *
  from public.kpi_import_rows
  where tenant_id = p_tenant_id
    and is_valid
    and occurred_on between p_from and p_to
    and public.hub_has_permission(p_tenant_id, 'kpi.read')
), totals as (
  select
    coalesce(sum(amount) filter (where data_kind = 'revenue'), 0) as revenue,
    coalesce(sum(amount) filter (where data_kind = 'cost'), 0) as other_cost,
    coalesce(sum(amount) filter (where data_kind = 'fuel'), 0) as fuel_cost,
    coalesce(sum(available_hours) filter (where data_kind = 'vehicle_activity'), 0) as available_hours,
    coalesce(sum(occupied_hours) filter (where data_kind = 'vehicle_activity'), 0) as occupied_hours,
    coalesce(sum(paid_hours) filter (where data_kind = 'driver_time'), 0) as paid_hours,
    coalesce(sum(billable_hours) filter (where data_kind = 'driver_time'), 0) as billable_hours,
    count(distinct nullif(vehicle_registration, '')) filter (where data_kind = 'revenue') as revenue_vehicle_count
  from scoped
), vehicles as (
  select coalesce(nullif(vehicle_registration, ''), 'Ej kopplad') as vehicle,
    coalesce(sum(amount) filter (where data_kind = 'revenue'), 0) as revenue,
    coalesce(sum(amount) filter (where data_kind = 'cost'), 0) as cost,
    coalesce(sum(amount) filter (where data_kind = 'fuel'), 0) as fuel_cost,
    coalesce(sum(available_hours), 0) as available_hours,
    coalesce(sum(occupied_hours), 0) as occupied_hours
  from scoped
  where vehicle_registration is not null
  group by 1
  order by revenue desc, vehicle
), drivers as (
  select coalesce(nullif(employee_number, ''), 'Ej kopplad') as employee,
    coalesce(sum(paid_hours), 0) as paid_hours,
    coalesce(sum(billable_hours), 0) as billable_hours
  from scoped
  where data_kind = 'driver_time' and employee_number is not null
  group by 1
  order by billable_hours desc, employee
), quality as (
  select
    count(*) as total_rows,
    count(*) filter (where is_valid) as valid_rows,
    count(*) filter (where vehicle_registration is null and data_kind in ('revenue','cost','fuel','vehicle_activity')) as rows_without_vehicle,
    count(*) filter (where employee_number is null and data_kind = 'driver_time') as rows_without_employee
  from public.kpi_import_rows
  where tenant_id = p_tenant_id and occurred_on between p_from and p_to
    and public.hub_has_permission(p_tenant_id, 'kpi.read')
)
select jsonb_build_object(
  'period', jsonb_build_object('from', p_from, 'to', p_to),
  'metrics', jsonb_build_object(
    'revenue', totals.revenue,
    'result', totals.revenue - totals.other_cost - totals.fuel_cost,
    'revenue_per_vehicle', case when totals.revenue_vehicle_count > 0 then totals.revenue / totals.revenue_vehicle_count else 0 end,
    'vehicle_utilization', case when totals.available_hours > 0 then totals.occupied_hours / totals.available_hours * 100 else 0 end,
    'diesel_share', case when totals.revenue > 0 then totals.fuel_cost / totals.revenue * 100 else 0 end,
    'driver_billability', case when totals.paid_hours > 0 then totals.billable_hours / totals.paid_hours * 100 else 0 end
  ),
  'components', jsonb_build_object(
    'other_cost', totals.other_cost,
    'fuel_cost', totals.fuel_cost,
    'available_hours', totals.available_hours,
    'occupied_hours', totals.occupied_hours,
    'paid_hours', totals.paid_hours,
    'billable_hours', totals.billable_hours,
    'revenue_vehicle_count', totals.revenue_vehicle_count
  ),
  'vehicles', coalesce((select jsonb_agg(to_jsonb(vehicles)) from vehicles), '[]'::jsonb),
  'drivers', coalesce((select jsonb_agg(to_jsonb(drivers)) from drivers), '[]'::jsonb),
  'quality', to_jsonb(quality)
)
from totals cross join quality;
$$;

revoke all on function public.kpi_transport_dashboard(uuid, date, date) from public, anon;
grant execute on function public.kpi_transport_dashboard(uuid, date, date) to authenticated;
