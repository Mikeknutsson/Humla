create or replace function public.hub_stena_settlement_workspace(
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
  select a.portal_ids[1] as booking_id, sum((a.before_fact->>'amount')::numeric) as amount,
   array_agg(distinct nullif(btrim(a.before_fact#>>'{original,Ordernummer}'),'') order by nullif(btrim(a.before_fact#>>'{original,Ordernummer}'),''))
    filter(where nullif(btrim(a.before_fact#>>'{original,Ordernummer}'),'') is not null) as workify_orders
  from active_matches a
  where cardinality(a.portal_ids) = 1
  group by a.portal_ids[1]
 ), workify_rows as materialized (
  select f.fact_id, f.occurred_on, f.vehicle, f.amount,
   coalesce(f.original->>'Littranummer','') as reference,
   array_remove(array[nullif(btrim(f.original->>'Ordernummer'),'')],null) as workify_orders,
   regexp_replace(upper(coalesce(nullif(f.original->>'RegNr',''),f.vehicle)), '[^A-Z0-9]', '', 'g') as registration,
   array(select (number)[1] from regexp_matches(coalesce(f.original->>'Littranummer','') || ' ' ||
    coalesce(f.original->>'ArtikelKommentar',''), '(?<![0-9])[0-9]{8}(?![0-9])', 'g') number) as booking_numbers
  from private.hub_kpi_prepared_facts f
  where f.tenant_id = p_tenant and f.generation_id = active_report
    and f.occurred_on >= p_month and f.occurred_on < next_month and f.kind = 'revenue' and f.source = 'Workify'
    and f.original->>'Kundnamn' in ('Elleholms Maskin (STENA)', 'Stena Recycling AB')
    and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
 ), reserved_bookings as (
  select unnest(a.portal_ids) as id from active_matches a
  union
  select b.revenue_object_id from bookings b
  join (select distinct unnest(booking_numbers) as booking from workify_rows) w using (booking)
 ), fallback_candidates as (
  select b.revenue_object_id as booking_id, w.fact_id, w.amount,
   count(*) over(partition by b.revenue_object_id) as by_booking,
   count(*) over(partition by w.fact_id) as by_workify
  from bookings b
  join workify_rows w on w.occurred_on = b.occurred_on
   and w.registration = regexp_replace(upper(b.registration), '[^A-Z0-9]', '', 'g')
   and w.amount = b.amount
  where b.occurred_on >= p_month and b.occurred_on < next_month
   and w.registration ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' and w.amount <> 0
   and cardinality(w.booking_numbers) = 0
   and not exists(select 1 from reserved_bookings r where r.id = b.revenue_object_id)
 ), fallback as materialized (
  select c.booking_id,c.fact_id,c.amount,w.workify_orders
  from fallback_candidates c join workify_rows w using(fact_id)
  where c.by_booking = 1 and c.by_workify = 1
 ), comparison as (
  select b.revenue_object_id::text as id, b.booking, b.occurred_on as date,
   b.registration, coalesce(m.amount,a.amount) as workify, h.amount as history, s.amount as settled,
   h.file_name as history_file, s.file_name as settled_file,
   s.amount - h.amount as settlement_difference, coalesce(m.amount,a.amount) - coalesce(o.amount,b.amount) as workify_difference,
   case
    when coalesce(o.amount,b.amount) is null then 'missing_amount'
    when abs(coalesce(m.amount,a.amount) - coalesce(o.amount,b.amount)) >= 1 or abs(s.amount - h.amount) >= 1 then 'difference'
    when active_report is not null and coalesce(m.amount,a.amount) is null then 'portal_only'
    when s.amount is null then 'open'
    else 'matched'
   end as status,
   case when a.fact_id is not null then 'registration_date_amount' when m.booking_id is not null then 'booking' end as match_method,
   a.fact_id as fallback_fact_id, coalesce(m.workify_orders,a.workify_orders,array[]::text[]) as workify_orders
  from bookings b
  left join source_rows h on h.revenue_object_id = b.revenue_object_id and h.source_kind = 'history'
  left join source_rows s on s.revenue_object_id = b.revenue_object_id and s.source_kind = 'settled'
  left join matches m on m.booking_id = b.revenue_object_id
  left join fallback a on a.booking_id = b.revenue_object_id
  left join private.hub_stena_amount_overrides_v1 o on o.tenant_id = p_tenant and o.revenue_object_id = b.revenue_object_id
  where b.occurred_on >= p_month and b.occurred_on < next_month
  union all
  select 'workify:' || w.fact_id, w.reference, w.occurred_on, w.vehicle, w.amount,
   null, null, null, null, null, null, 'workify_only', null, null, w.workify_orders
  from workify_rows w where not exists(select 1 from fallback a where a.fact_id=w.fact_id)
  union all
  select 'workify:' || a.fact_id, coalesce(a.before_fact#>>'{original,Littranummer}',''),
   (a.before_fact->>'occurred_on')::date, a.before_fact->>'vehicle', (a.before_fact->>'amount')::numeric,
   null, null, null, null, null, null, 'multiple_bookings', null, null, array_remove(array[nullif(btrim(a.before_fact#>>'{original,Ordernummer}'),'')],null)
  from active_matches a
  where cardinality(a.portal_ids) > 1
 ), fingerprints as (
  select c.*, md5(jsonb_build_array(c.booking,c.date,c.registration,c.workify,c.history,c.settled,
   c.workify_difference,c.settlement_difference,c.status)::text || coalesce(':' || c.fallback_fact_id,'')) as fingerprint
  from comparison c
 ), prioritized as (
  select c.*,
   c.workify - c.settled as shortfall,
   case when c.settled is null then c.workify - c.history end as history_shortfall,
   coalesce(c.settled is null and c.workify >= 200 and c.workify - c.history < 200,false) as awaiting_settlement,
   c.workify is null and c.settled is not null and active_report is not null as settled_only,
   case
    when c.workify is null then null
    when c.settled is not null then case when c.workify - c.settled >= 200 then 'underpaid' end
    when c.workify < 200 then null
    when c.status in ('workify_only','multiple_bookings') then 'needs_match'
    when c.history is null then 'missing_history_amount'
    when c.workify - c.history >= 200 then 'history_difference'
   end as review_reason
  from fingerprints c
 ), reviewed as (
  select c.*, coalesce(e.revision,0) as revision, e.note, e.updated_at,
   case when e.fingerprint is distinct from c.fingerprint then 'todo' else e.state end as review_state,
   coalesce(e.fingerprint <> c.fingerprint,false) as changed_since_review,
   c.review_reason is not null and
   (e.state is distinct from 'reviewed' or e.fingerprint is distinct from c.fingerprint) as needs_review
  from prioritized c
  left join lateral (
   select revision, note, state, fingerprint, updated_at from private.hub_stena_review_events e
   where e.tenant_id=p_tenant and e.row_id=c.id order by revision desc limit 1
  ) e on true
 ), totals as (
  select count(*) as rows, count(*) filter(where needs_review) as review_rows,
   count(*) filter(where review_state = 'reviewed') as reviewed_rows,
   count(*) filter(where match_method = 'registration_date_amount') as fallback_rows,
   sum(shortfall) filter(where needs_review and review_reason='underpaid') as review_amount,
   count(*) filter(where awaiting_settlement) as awaiting_rows,
   sum(workify) filter(where awaiting_settlement) as awaiting_amount,
   count(*) filter(where settled_only) as settled_only_rows,
   sum(settled) filter(where settled_only) as settled_only_amount,
   sum(workify) as workify, sum(history) as history, sum(settled) as settled
  from reviewed
 ), coverage as (
  select case
   when workify is not null and settled is not null then 'matched_settled'
   when workify is not null and history is not null then 'matched_history'
   when workify is not null then 'workify_only'
   when settled is not null then 'settled_only'
   else 'history_other'
  end as category, count(*) as rows, sum(workify) as workify, sum(history) as history, sum(settled) as settled
  from reviewed group by 1
 ), settled_only_vehicles as (
  select registration, count(*) as bookings, sum(settled) as amount
  from reviewed where settled_only
  group by registration
 ), filtered as (
  select * from reviewed where not settled_only and (not coalesce(p_only_review,false) or needs_review)
 ), page as (
  select *, row_number() over(order by
   case when p_only_review then case review_reason
    when 'underpaid' then 0 when 'history_difference' then 1 else 2 end end,
   case when p_only_review then coalesce(shortfall,history_shortfall,workify) end desc, date desc, id) as display_order
  from filtered order by display_order offset p_page * 80 limit 80
 )
 select jsonb_build_object(
  'report_available', active_report is not null,
  'totals', (select to_jsonb(t) from totals t),
  'settled_only_vehicles', coalesce((select jsonb_agg(to_jsonb(v) order by v.amount desc,v.registration) from settled_only_vehicles v), '[]'::jsonb),
  'coverage', coalesce((select jsonb_object_agg(c.category,to_jsonb(c)-'category') from coverage c),'{}'::jsonb),
  'filtered_count', (select count(*) from filtered),
  'rows', coalesce((select jsonb_agg(to_jsonb(p) - 'display_order' order by p.display_order) from page p), '[]'::jsonb)
 ) into result;
 return result;
end;
$$;

revoke all on function public.hub_stena_settlement_workspace(uuid,date,integer,boolean) from public, anon, authenticated;
grant execute on function public.hub_stena_settlement_workspace(uuid,date,integer,boolean) to authenticated;

