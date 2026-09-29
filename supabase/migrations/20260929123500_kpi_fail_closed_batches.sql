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
with eligible as (
  select r.*
  from public.kpi_import_rows r
  join public.kpi_import_batches b on b.id = r.batch_id and b.tenant_id = r.tenant_id
  where r.tenant_id = p_tenant_id
    and b.status in ('completed', 'needs_review')
    and r.occurred_on between p_from and p_to
    and public.hub_has_permission(p_tenant_id, 'kpi.read')
), scoped as (
  select * from eligible where is_valid
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
  'quality', to_jsonb(quality)
)
from totals cross join quality;
$$;

revoke all on function public.kpi_transport_dashboard(uuid, date, date) from public, anon;
grant execute on function public.kpi_transport_dashboard(uuid, date, date) to authenticated;
