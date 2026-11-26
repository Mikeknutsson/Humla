create function private.hub_saw_fortnox_snapshot(p_tenant uuid,p_from date,p_to date)
returns table(payload jsonb,resource text)
language sql stable set search_path='' as $$
 select f.payload,f.resource
 from public.hub_fortnox_raw f
 where f.tenant_id=p_tenant and f.resource in ('saw_article_check_v1','saw_article_export_v1')
  and f.payload->>'from'<=p_from::text and f.payload->>'to'>=p_from::text
  and jsonb_typeof(f.payload->'rows')='array'
 order by least((f.payload->>'to')::date,p_to) desc,(f.resource='saw_article_check_v1') desc,f.fetched_at desc
 limit 1
$$;
revoke all on function private.hub_saw_fortnox_snapshot(uuid,date,date) from public,anon,authenticated;

create function private.hub_foreman_facts_with_saw_invoices(p_tenant uuid,p_from date,p_to date,p_user uuid)
returns setof private.hub_kpi_prepared_display_facts
language sql stable set search_path='' as $$
 with base as materialized (
  select * from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user)
 ), saw as materialized (
  select r.unit_id,s.active_generation generation_id
  from private.hub_saw_activity_rules_v1 r join private.hub_kpi_report_state s using (tenant_id)
  where r.tenant_id=p_tenant
 ), scope_members as materialized (
  select m.user_id,p.cost_centers
  from public.hub_tenant_members m
  left join private.hub_foreman_access_plans p on p.tenant_id=m.tenant_id and p.auth_user_id=m.user_id and p.status='active'
  where m.tenant_id=p_tenant and m.status='active' and (
   (p_user='00000000-0000-0000-0000-000000000030'::uuid
    and trim(m.display_name) ~* '^(marcus|ola|pierre)([[:space:]]|$)')
    or (p_user is distinct from '00000000-0000-0000-0000-000000000030'::uuid and m.user_id=coalesce(p_user,auth.uid()))
  )
 ), owner_scope as (
  select exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant
   and m.user_id=auth.uid() and m.role='owner' and m.status='active') and
   (p_user is null or p_user='00000000-0000-0000-0000-000000000030'::uuid) allowed
 ), snapshot as materialized (
  select * from private.hub_saw_fortnox_snapshot(p_tenant,p_from,p_to)
 ), coverage as (
  select least((payload->>'to')::date,p_to) covered_to, resource from snapshot
  union all
  select p_to,'confirmed_invoice_statistics'
  where not exists(select 1 from snapshot) and p_from>=date '2025-09-01' and p_to<=date '2026-08-31'
   and exists(select 1 from private.hub_saw_invoice_lines_v1 where tenant_id=p_tenant)
 ), allowed_days as materialized (
  select dates.day::date occurred_on,c.covered_to,c.resource,s.unit_id,s.generation_id
  from coverage c cross join saw s
  cross join lateral generate_series(p_from::timestamp,c.covered_to::timestamp,interval '1 day') dates(day)
  where (select allowed from owner_scope) or exists (
   select 1 from scope_members m where case when m.cost_centers is not null then '30'=any(m.cost_centers)
    else exists(select 1 from public.hub_transport_leader_units a
     where a.tenant_id=p_tenant and a.user_id=m.user_id and a.unit_id=s.unit_id
      and a.valid_from<=dates.day::date and (a.valid_to is null or a.valid_to>=dates.day::date))
    end
  )
 ), invoice_lines as (
  select l.date occurred_on,l.amount
  from snapshot x
  cross join lateral jsonb_to_recordset(x.payload->'rows') l(date date,article text,amount numeric)
  where l.article in ('12-04','12-041') and l.date between p_from and p_to
  union all
  select l.occurred_on,l.amount from private.hub_saw_invoice_lines_v1 l
  where l.tenant_id=p_tenant and l.occurred_on between p_from and p_to
   and exists(select 1 from coverage c where c.resource='confirmed_invoice_statistics')
 ), invoiced as (
  select occurred_on,sum(amount) amount from invoice_lines group by 1
 )
 select f.generation_id,f.tenant_id,f.fiscal_year,f.fact_id,f.occurred_on,f.kind,
  case when d.occurred_on is not null then f.amount-coalesce((f.original#>>'{_humla_saw_activity,original_amount}')::numeric,0)
   else f.amount end,
  f.category,f.project,f.vehicle,f.unit_id,f.unit_name,f.business_group,f.source,f.cost_center,
  case when d.occurred_on is not null then f.original||jsonb_build_object('_humla_saw_fortnox',jsonb_build_object(
    'resource',d.resource,'covered_to',d.covered_to,'kind','truck_allocation')) else f.original end
 from base f left join allowed_days d on d.occurred_on=f.occurred_on and d.unit_id=f.unit_id
  and f.kind='revenue' and f.original#>>'{_humla_saw_activity,reason}'='article_hour_split'
  and f.original#>>'{_humla_saw_activity,branch}'='saw'
 union all
 select d.generation_id,p_tenant,extract(year from d.occurred_on)::int-case when extract(month from d.occurred_on)<9 then 1 else 0 end,
  'saw-invoice-net:'||d.occurred_on,d.occurred_on,'revenue',coalesce(i.amount,0),'transport',null,null,
  d.unit_id,'Sågning','Sågning',case when d.resource='confirmed_invoice_statistics' then 'Artikelstatistik' else 'Fortnox' end,'30',
  jsonb_build_object('_humla_saw_fortnox',jsonb_build_object('resource',d.resource,'covered_to',d.covered_to,'kind','invoice_net'))
 from allowed_days d left join invoiced i using (occurred_on)
 where i.occurred_on is not null or d.occurred_on=(select min(occurred_on) from allowed_days)
$$;
revoke all on function private.hub_foreman_facts_with_saw_invoices(uuid,date,date,uuid) from public,anon,authenticated;

do $migration$
declare definition text; replacement text; entry regprocedure; marker text;
begin
 entry:='public.hub_saw_activity_report_v1(uuid,date,date,uuid,uuid,integer[])'::regprocedure;
 definition:=pg_get_functiondef(entry);
 replacement:=regexp_replace(definition,'  select f\.payload, f\.resource into invoice_snapshot,invoice_source[[:space:]]+from public\.hub_fortnox_raw f[^;]+;', '  select payload,resource into invoice_snapshot,invoice_source from private.hub_saw_fortnox_snapshot(p_tenant,p_from,p_to);');
 if replacement=definition then raise exception 'Saw activity snapshot lookup not found'; end if;
 execute replacement;

 entry:='private.hub_foreman_scorecard_v1(uuid,date,date,uuid,uuid,integer,integer[],text,boolean)'::regprocedure;
 definition:=pg_get_functiondef(entry);
 marker:='private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user)';
 if strpos(definition,marker)=0 then raise exception 'Foreman finance source not found'; end if;
 definition:=replace(definition,marker,'private.hub_foreman_facts_with_saw_invoices(p_tenant,p_from,p_to,p_user)');
 marker:=$text$'saw_breakdown',(select case when count(*)>0 then jsonb_build_object($text$;
 if strpos(definition,marker)=0 then raise exception 'Saw breakdown not found'; end if;
 execute replace(definition,marker,marker||$text$
 'invoice_covered_to',max(original#>>'{_humla_saw_fortnox,covered_to}'),
 'invoice_source',max(original#>>'{_humla_saw_fortnox,resource}'),
 'invoice_net',sum(amount)filter(where original#>>'{_humla_saw_fortnox,kind}'='invoice_net'),$text$);

 entry:='public.hub_foreman_result_trend_v1(uuid,date,date,uuid)'::regprocedure;
 definition:=pg_get_functiondef(entry);
 marker:='private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user)';
 if strpos(definition,marker)=0 then raise exception 'Foreman trend source not found'; end if;
 execute replace(definition,marker,'private.hub_foreman_facts_with_saw_invoices(p_tenant,p_from,p_to,p_user)');
end
$migration$;
