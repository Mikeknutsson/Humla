create table public.kpi_account_mappings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.hub_tenants(id) on delete cascade,
  account_from integer not null check (account_from between 0 and 99999999),
  account_to integer not null check (account_to between 0 and 99999999 and account_to >= account_from),
  name text not null check (length(trim(name)) between 1 and 120),
  calculation_role text not null check (calculation_role in ('cost','fuel','exclude')),
  cost_category text not null check (cost_category in ('personnel','fuel','service_repair','fixed','other','ballast','disposal')),
  include_in_vehicle_result boolean not null default true,
  priority integer not null default 100 check (priority between 0 and 10000),
  valid_from date not null,
  valid_to date,
  enabled boolean not null default true,
  notes text,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (valid_to is null or valid_to >= valid_from),
  check (calculation_role <> 'fuel' or cost_category = 'fuel'),
  unique (tenant_id, account_from, account_to, valid_from)
);

create index kpi_account_mappings_lookup_idx
on public.kpi_account_mappings (tenant_id, account_from, account_to, priority desc, valid_from desc)
where enabled;

create index kpi_account_mappings_created_by_idx on public.kpi_account_mappings (created_by);
create index kpi_account_mappings_updated_by_idx on public.kpi_account_mappings (updated_by);

create table public.kpi_account_mapping_events (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.hub_tenants(id) on delete cascade,
  mapping_id uuid not null,
  event_type text not null check (event_type in ('created','updated','deleted')),
  old_data jsonb,
  new_data jsonb,
  changed_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index kpi_account_mapping_events_mapping_idx
on public.kpi_account_mapping_events (mapping_id, created_at desc);
create index kpi_account_mapping_events_tenant_idx on public.kpi_account_mapping_events (tenant_id, created_at desc);
create index kpi_account_mapping_events_actor_idx on public.kpi_account_mapping_events (changed_by);

alter table public.kpi_account_mappings enable row level security;
alter table public.kpi_account_mapping_events enable row level security;

revoke all on public.kpi_account_mappings, public.kpi_account_mapping_events from anon;
grant select, insert, update, delete on public.kpi_account_mappings to authenticated;
grant select on public.kpi_account_mapping_events to authenticated;

create policy kpi_account_mappings_read on public.kpi_account_mappings
for select to authenticated
using (public.hub_has_permission(tenant_id, 'kpi.read'));

create policy kpi_account_mappings_insert on public.kpi_account_mappings
for insert to authenticated
with check (
  public.hub_has_permission(tenant_id, 'kpi.manage')
  and created_by = (select auth.uid())
  and updated_by = (select auth.uid())
);

create policy kpi_account_mappings_update on public.kpi_account_mappings
for update to authenticated
using (public.hub_has_permission(tenant_id, 'kpi.manage'))
with check (
  public.hub_has_permission(tenant_id, 'kpi.manage')
  and updated_by = (select auth.uid())
);

create policy kpi_account_mappings_delete on public.kpi_account_mappings
for delete to authenticated
using (public.hub_has_permission(tenant_id, 'kpi.manage'));

create policy kpi_account_mapping_events_read on public.kpi_account_mapping_events
for select to authenticated
using (public.hub_has_permission(tenant_id, 'kpi.read'));

create or replace function private.kpi_log_account_mapping_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if auth.uid() is null then
    raise exception 'Authenticated actor required';
  end if;
  insert into public.kpi_account_mapping_events (
    tenant_id, mapping_id, event_type, old_data, new_data, changed_by
  ) values (
    coalesce(new.tenant_id, old.tenant_id),
    coalesce(new.id, old.id),
    case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end,
    (select auth.uid())
  );
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.kpi_log_account_mapping_event() from public, anon, authenticated;

create trigger kpi_account_mapping_audit
after insert or update or delete on public.kpi_account_mappings
for each row execute function private.kpi_log_account_mapping_event();

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
with eligible_base as (
  select r.*,
    case when trim(r.account) ~ '^[0-9]{1,8}$' then trim(r.account)::integer else null end as account_number
  from public.kpi_import_rows r
  join public.kpi_import_batches b on b.id = r.batch_id and b.tenant_id = r.tenant_id
  where r.tenant_id = p_tenant_id
    and b.status in ('completed', 'needs_review')
    and r.occurred_on between p_from and p_to
    and public.hub_has_permission(p_tenant_id, 'kpi.read')
), eligible as (
  select e.*,
    m.id as account_mapping_id,
    m.calculation_role as mapped_role,
    m.cost_category,
    coalesce(m.include_in_vehicle_result, true) as include_in_vehicle_result,
    case
      when e.data_kind = 'revenue' then 'revenue'
      when e.data_kind = 'fuel' then 'fuel'
      when e.data_kind = 'cost' and m.id is null then 'unmapped'
      when e.data_kind = 'cost' then m.calculation_role
      else e.data_kind
    end as calculation_role
  from eligible_base e
  left join lateral (
    select am.*
    from public.kpi_account_mappings am
    where e.data_kind = 'cost'
      and e.account_number is not null
      and am.tenant_id = e.tenant_id
      and am.enabled
      and e.account_number between am.account_from and am.account_to
      and e.occurred_on >= am.valid_from
      and (am.valid_to is null or e.occurred_on <= am.valid_to)
    order by am.priority desc, (am.account_to - am.account_from) asc, am.valid_from desc, am.created_at desc
    limit 1
  ) m on true
), scoped as (
  select * from eligible
  where is_valid and calculation_role <> 'unmapped'
), totals as (
  select
    coalesce(sum(amount) filter (where calculation_role = 'revenue'), 0) as revenue,
    coalesce(sum(amount) filter (where calculation_role = 'cost'), 0) as other_cost,
    coalesce(sum(amount) filter (where calculation_role = 'fuel'), 0) as fuel_cost,
    coalesce(sum(available_hours) filter (where data_kind = 'vehicle_activity'), 0) as available_hours,
    coalesce(sum(occupied_hours) filter (where data_kind = 'vehicle_activity'), 0) as occupied_hours,
    coalesce(sum(paid_hours) filter (where data_kind = 'driver_time'), 0) as paid_hours,
    coalesce(sum(billable_hours) filter (where data_kind = 'driver_time'), 0) as billable_hours,
    count(distinct nullif(vehicle_registration, '')) filter (where calculation_role = 'revenue') as revenue_vehicle_count
  from scoped
), vehicles as (
  select coalesce(nullif(vehicle_registration, ''), 'Ej kopplad') as vehicle,
    coalesce(sum(amount) filter (where calculation_role = 'revenue'), 0) as revenue,
    coalesce(sum(amount) filter (where calculation_role = 'cost' and include_in_vehicle_result), 0) as cost,
    coalesce(sum(amount) filter (where calculation_role = 'fuel' and include_in_vehicle_result), 0) as fuel_cost,
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
), category_totals as (
  select cost_category as category, coalesce(sum(amount), 0) as amount
  from scoped
  where calculation_role in ('cost','fuel') and cost_category is not null
  group by cost_category
  order by cost_category
), unmapped_accounts as (
  select coalesce(account, 'Konto saknas') as account,
    min(description) as description,
    count(*) as row_count,
    coalesce(sum(amount), 0) as amount
  from eligible
  where data_kind = 'cost' and account_mapping_id is null
  group by account
  order by abs(coalesce(sum(amount), 0)) desc, account
), quality as (
  select
    count(*) as total_rows,
    count(*) filter (where is_valid and calculation_role <> 'unmapped') as valid_rows,
    count(*) filter (where data_kind = 'cost' and calculation_role = 'unmapped') as rows_without_account_mapping,
    count(*) filter (where vehicle_registration is null and data_kind in ('revenue','cost','fuel','vehicle_activity')) as rows_without_vehicle,
    count(*) filter (where employee_number is null and data_kind = 'driver_time') as rows_without_employee
  from eligible
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
  'cost_categories', coalesce((select jsonb_object_agg(category, amount) from category_totals), '{}'::jsonb),
  'unmapped_accounts', coalesce((select jsonb_agg(to_jsonb(unmapped_accounts)) from unmapped_accounts), '[]'::jsonb),
  'quality', to_jsonb(quality)
)
from totals cross join quality;
$$;

revoke all on function public.kpi_transport_dashboard(uuid, date, date) from public, anon;
grant execute on function public.kpi_transport_dashboard(uuid, date, date) to authenticated;
