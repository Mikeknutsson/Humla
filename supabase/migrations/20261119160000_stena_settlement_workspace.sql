create function public.hub_stena_settlement_workspace(
 p_tenant uuid, p_month date, p_page integer default 0, p_only_review boolean default false
)
returns jsonb
language plpgsql stable security definer
set search_path = ''
set statement_timeout = '15s'
set jit = 'off'
as $$
declare
 next_month date;
 active_report uuid;
 result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant, 'kpi.manage') then
  raise exception 'Access denied' using errcode = '42501';
 end if;
 if p_month is null or extract(day from p_month) <> 1
    or p_page is null or p_page not between 0 and 1000 then
  raise exception 'Invalid period or page' using errcode = '22023';
 end if;
 next_month := (p_month + interval '1 month')::date;

 select s.active_generation into active_report
 from private.hub_kpi_report_state s where s.tenant_id = p_tenant;

 with source_rows as materialized (
  select distinct on (r.revenue_object_id, f.source_kind)
   r.revenue_object_id, r.booking, r.occurred_on, r.registration,
   r.amount, f.source_kind, f.file_name
  from private.hub_stena_rows_v1 r
  join private.hub_stena_files_v1 f using (tenant_id, file_hash)
  where r.tenant_id = p_tenant and f.complete
  order by r.revenue_object_id, f.source_kind, f.uploaded_at desc, f.file_hash
 ), bookings as materialized (
  select distinct on (s.revenue_object_id)
   s.revenue_object_id, s.booking, s.occurred_on, s.registration, s.source_kind, s.amount
  from source_rows s
  order by s.revenue_object_id, (s.source_kind = 'settled') desc
 ), active_matches as materialized (
  select a.fact_id, a.before_fact, a.portal_ids
  from private.hub_stena_projection_audit_v1 a
  left join bookings b on cardinality(a.portal_ids) = 1 and b.revenue_object_id = a.portal_ids[1]
  left join lateral (
   select true as retained from private.hub_kpi_prepared_facts f
   where f.tenant_id = p_tenant and f.generation_id = active_report and f.fact_id = a.fact_id
   limit 1
  ) current_fact on true
  where a.tenant_id = p_tenant and a.generation_id = active_report
    and current_fact.retained is null
    and case when cardinality(a.portal_ids) = 1
         then b.occurred_on >= p_month and b.occurred_on < next_month
         else (a.before_fact->>'occurred_on')::date >= p_month
           and (a.before_fact->>'occurred_on')::date < next_month
        end
 ), matches as (
  select a.portal_ids[1] as booking_id, sum((a.before_fact->>'amount')::numeric) as amount
  from active_matches a
  where cardinality(a.portal_ids) = 1
  group by a.portal_ids[1]
 ), comparison as (
  select b.revenue_object_id::text as id, b.booking, b.occurred_on as date,
   b.registration, m.amount as workify, h.amount as history, s.amount as settled,
   h.file_name as history_file, s.file_name as settled_file,
   s.amount - h.amount as settlement_difference, m.amount - coalesce(o.amount,b.amount) as workify_difference,
   case
    when coalesce(o.amount,b.amount) is null then 'missing_amount'
    when abs(m.amount - coalesce(o.amount,b.amount)) >= 1 or abs(s.amount - h.amount) >= 1 then 'difference'
    when active_report is not null and m.amount is null then 'portal_only'
    when s.amount is null then 'open'
    else 'matched'
   end as status
  from bookings b
  left join source_rows h on h.revenue_object_id = b.revenue_object_id and h.source_kind = 'history'
  left join source_rows s on s.revenue_object_id = b.revenue_object_id and s.source_kind = 'settled'
  left join matches m on m.booking_id = b.revenue_object_id
  left join private.hub_stena_amount_overrides_v1 o on o.tenant_id = p_tenant and o.revenue_object_id = b.revenue_object_id
  where b.occurred_on >= p_month and b.occurred_on < next_month
  union all
  select 'workify:' || f.fact_id, coalesce(f.original->>'Littranummer',''), f.occurred_on, f.vehicle, f.amount,
   null, null, null, null, null, null, 'workify_only'
  from private.hub_kpi_prepared_facts f
  where f.tenant_id = p_tenant and f.generation_id = active_report
    and f.occurred_on >= p_month and f.occurred_on < next_month and f.kind = 'revenue' and f.source = 'Workify'
    and f.original->>'Kundnamn' in ('Elleholms Maskin (STENA)', 'Stena Recycling AB')
    and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
  union all
  select 'workify:' || a.fact_id, coalesce(a.before_fact#>>'{original,Littranummer}',''),
   (a.before_fact->>'occurred_on')::date, a.before_fact->>'vehicle', (a.before_fact->>'amount')::numeric,
   null, null, null, null, null, null, 'multiple_bookings'
  from active_matches a
  where cardinality(a.portal_ids) > 1
 ), totals as (
  select count(*) as rows, count(*) filter(where status not in ('open','matched')) as review_rows,
   sum(workify) as workify, sum(history) as history, sum(settled) as settled
  from comparison
 ), filtered as (
  select * from comparison where not coalesce(p_only_review,false) or status not in ('open','matched')
 ), page as (
  select * from filtered order by date desc, id offset p_page * 80 limit 80
 )
 select jsonb_build_object(
  'report_available', active_report is not null,
  'totals', (select to_jsonb(t) from totals t),
  'filtered_count', (select count(*) from filtered),
  'rows', coalesce((select jsonb_agg(to_jsonb(p) order by p.date desc, p.id) from page p), '[]'::jsonb)
 ) into result;
 return result;
end;
$$;

revoke all on function public.hub_stena_settlement_workspace(uuid,date,integer,boolean) from public, anon, authenticated;
grant execute on function public.hub_stena_settlement_workspace(uuid,date,integer,boolean) to authenticated;
