-- Resolve exact, confirmed, dated memberships before collecting unresolved facts.
create table private.hub_remaining_unit_routing_audit(
 tenant_id uuid not null,generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade,
 fact_id text not null,before_record jsonb not null,after_record jsonb not null,actor uuid not null,
 created_at timestamptz not null default now(),primary key(generation_id,fact_id)
);
alter table private.hub_remaining_unit_routing_audit enable row level security;
revoke all on private.hub_remaining_unit_routing_audit from public,anon,authenticated;
create or replace function private.hub_resolve_remaining_units_v1(p_tenant uuid,p_generation uuid)
returns jsonb language plpgsql set search_path='' set plan_cache_mode='force_custom_plan' set jit='off' as $$
declare fallback uuid; resolved integer; remaining integer;before_count bigint;before_amount numeric;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'KPI management required' using errcode='42501';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant)then raise exception 'Generation tenant mismatch';end if;
 select id into fallback from public.hub_objects where tenant_id=p_tenant and object_type='EconomicUnit' and data->>'report_fallback'='unresolved';
 if fallback is null then return jsonb_build_object('resolved',0,'remaining',0);end if;
 select count(*),sum(amount)into before_count,before_amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 with members as materialized(
  select o.id,p.value->>'name' name,p.value->>'valid_from' vf,p.value->>'valid_to' vt,
   p.value->>'business_group_id' group_id,m.value->>'kind' kind,m.value->>'source_reference' ref
  from public.hub_objects o cross join lateral jsonb_array_elements(o.data->'periods')p
  cross join lateral jsonb_array_elements(p.value->'members')m
  where o.tenant_id=p_tenant and o.object_type='EconomicUnit' and coalesce((p.value->>'enabled')::boolean,false)
   and m.value->>'resolution'='confirmed' and m.value->>'object_id' is not null
 ), candidates as materialized(
  select f.fact_id,f.project,f.vehicle,f.cost_center,f.cost_center_name,f.business_group,f.unit_id,f.unit_name,
   m.id target_id,m.name target_name,m.group_id,
   case when f.project is not null then f.project
    when f.source='Workify' then nullif(trim(f.original->>'Projektnr'),'')
    when f.source='Avskrivningsregister' then substring(f.vehicle from '^(?:AO[[:space:]]*)?([0-9]+)[[:space:]]') end target_project
  from private.hub_kpi_prepared_facts f join members m on
   ((m.kind='project' and m.ref=coalesce(f.project,case when f.source='Workify' then nullif(trim(f.original->>'Projektnr'),'')
    when f.source='Avskrivningsregister' then substring(f.vehicle from '^(?:AO[[:space:]]*)?([0-9]+)[[:space:]]')end))
    or(m.kind='vehicle' and m.ref=f.vehicle))
   and f.occurred_on>=m.vf::date and(m.vt is null or f.occurred_on<=m.vt::date)
  where f.tenant_id=p_tenant and f.generation_id=p_generation and
   (f.unit_id is null or f.unit_id=fallback or not exists(select 1 from public.hub_objects o where o.tenant_id=p_tenant and o.id=f.unit_id and o.object_type='EconomicUnit'))
 ), unique_targets as(
  select fact_id,min(target_id::text)::uuid target_id from candidates group by fact_id having count(distinct target_id)=1
 ), targets as materialized(
  select distinct on(c.fact_id)c.*,coalesce(case when c.cost_center is null or c.cost_center='unclassified' then pc.cost_center end,c.cost_center) target_cost_center,
   coalesce(case when c.cost_center is null or c.cost_center='unclassified' then pc.cost_center_name end,c.cost_center_name) target_cost_center_name,
   coalesce(g.name,c.business_group) target_group
  from candidates c join unique_targets u on u.fact_id=c.fact_id and u.target_id=c.target_id
  join private.hub_kpi_prepared_facts f on f.generation_id=p_generation and f.tenant_id=p_tenant and f.fact_id=c.fact_id
  left join public.kpi_project_classification_periods pc on pc.tenant_id=p_tenant and pc.project_reference=c.target_project
   and f.occurred_on>=pc.valid_from and(pc.valid_to is null or f.occurred_on<=pc.valid_to)
  left join public.kpi_business_groups g on g.tenant_id=p_tenant and g.id::text=c.group_id
  where (c.unit_id,c.project) is distinct from(c.target_id,c.target_project)
  order by c.fact_id,pc.valid_from desc nulls last
 ), audit as(
  insert into private.hub_remaining_unit_routing_audit(tenant_id,generation_id,fact_id,before_record,after_record,actor)
  select p_tenant,p_generation,t.fact_id,jsonb_build_object('unit_id',t.unit_id,'project',t.project,'vehicle',t.vehicle,'cost_center',t.cost_center,'business_group',t.business_group),
   jsonb_build_object('unit_id',t.target_id,'project',t.target_project,'cost_center',t.target_cost_center,'reason','confirmed_dated_membership'),auth.uid() from targets t
  on conflict(generation_id,fact_id)do update set after_record=excluded.after_record returning fact_id
 )update private.hub_kpi_prepared_facts f set unit_id=t.target_id,unit_name=t.target_name,project=t.target_project,
  cost_center=t.target_cost_center,cost_center_name=t.target_cost_center_name,business_group=t.target_group,
  classification_source=(coalesce(f.classification_source,'{}')-'unresolved_unit')||jsonb_build_object('remaining_unit_resolution','confirmed_dated_membership'),
  display_original=(f.display_original-'_humla_unresolved_unit')||jsonb_build_object('_humla_unit_resolution','confirmed_dated_membership')
 from targets t join audit a on a.fact_id=t.fact_id where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=t.fact_id;
 get diagnostics resolved=row_count;
 with targets as materialized(
  select f.fact_id,f.unit_id,f.project,f.vehicle,f.cost_center,f.business_group,
   case when f.project is null and f.vehicle is null then 'missing_reference' else 'no_unique_dated_unit' end reason
  from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation and f.unit_id is distinct from fallback
   and not exists(select 1 from public.hub_objects o where o.tenant_id=p_tenant and o.id=f.unit_id and o.object_type='EconomicUnit')
 ),audit as(
  insert into private.hub_remaining_unit_routing_audit(tenant_id,generation_id,fact_id,before_record,after_record,actor)
  select p_tenant,p_generation,t.fact_id,jsonb_build_object('unit_id',t.unit_id,'project',t.project,'vehicle',t.vehicle,'cost_center',t.cost_center,'business_group',t.business_group),
   jsonb_build_object('unit_id',fallback,'reason',t.reason),auth.uid()from targets t
  on conflict(generation_id,fact_id)do update set after_record=excluded.after_record returning fact_id
 )update private.hub_kpi_prepared_facts f set unit_id=fallback,unit_name='Övrigt',
  classification_source=coalesce(f.classification_source,'{}')||jsonb_build_object('remaining_unit_resolution',t.reason,'unresolved_unit',true),
  display_original=f.display_original||jsonb_build_object('_humla_unit_resolution',t.reason,'_humla_unresolved_unit',true)
 from targets t join audit a on a.fact_id=t.fact_id where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=t.fact_id;
 get diagnostics remaining=row_count;
 update private.hub_kpi_prepared_display_facts d set unit_id=f.unit_id,unit_name=f.unit_name,project=f.project,vehicle=f.vehicle,
  cost_center=f.cost_center,business_group=f.business_group,original=f.display_original
 from private.hub_kpi_prepared_facts f join private.hub_remaining_unit_routing_audit a on a.generation_id=f.generation_id and a.fact_id=f.fact_id
 where f.generation_id=p_generation and f.tenant_id=p_tenant and d.generation_id=f.generation_id and d.tenant_id=f.tenant_id and d.fact_id=f.fact_id
 and (d.unit_id,d.unit_name,d.project,d.vehicle,d.cost_center,d.business_group,d.original)is distinct from(f.unit_id,f.unit_name,f.project,f.vehicle,f.cost_center,f.business_group,f.display_original);
 if row(before_count,before_amount)is distinct from(select row(count(*),sum(amount))from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation)then raise exception 'Unit resolution changed financial totals';end if;
 return jsonb_build_object('resolved',resolved,'newly_collected',remaining,'fallback_unit',fallback);
end $$;
revoke all on function private.hub_resolve_remaining_units_v1(uuid,uuid)from public,anon,authenticated;
-- Run after allocation on every new generation. Raw source rows are unchanged.
do $migration$
declare d text;needle text:='perform private.hub_prepare_billable_hours_v1(job.tenant_id,generation);';
begin
 d:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 if strpos(d,needle)=0 then raise exception 'Unexpected publication worker';end if;
 execute replace(d,needle,needle||chr(10)||'perform private.hub_resolve_remaining_units_v1(job.tenant_id,generation);');
end $migration$;
-- Övrigt has financial sums but no meaningful combined vehicle/time denominators.
CREATE OR REPLACE FUNCTION private.hub_kpi_mapped_units_projection_v1(p_tenant uuid, p_report jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb:=p_report; mapped jsonb; hidden jsonb; section text;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if jsonb_typeof(result->'economic_units')='array' then
  select coalesce(jsonb_agg(case when o.data->>'report_fallback'='unresolved' then e.value||jsonb_build_object('is_fallback',true,'worked_hours',null,'distance_mil',null,'utilization',null,'billing_percent',null,'revenue_per_hour',null,'cost_per_hour',null,'cost_per_mil',null,'revenue_per_mil',null,'fuel_cost_per_mil',null,'fuel_liters_per_mil',null)else e.value end order by e.ordinality) filter(where o.id is not null),'[]'::jsonb),
   jsonb_build_object('count',count(*) filter(where o.id is null),
    'revenue',coalesce(sum((e.value->>'revenue')::numeric) filter(where o.id is null),0),
    'cost',coalesce(sum((e.value->>'cost')::numeric) filter(where o.id is null),0))
  into mapped,hidden
  from jsonb_array_elements(result->'economic_units') with ordinality e(value,ordinality)
  left join public.hub_objects o on o.tenant_id=p_tenant and o.object_type='EconomicUnit' and o.id::text=e.value->>'key';
  result:=result||jsonb_build_object('economic_units',mapped,'economic_unit_scope','mapped','unmapped_economic_units',hidden);
 end if;
 foreach section in array array['month','ytd','previous'] loop
  if jsonb_typeof(result->section)='object' then
   result:=jsonb_set(result,array[section],private.hub_kpi_mapped_units_projection_v1(p_tenant,result->section));
  end if;
 end loop;
 result:=result||jsonb_build_object('material_unit_id',(select material_unit_id from private.hub_kpi_material_separation_settings where tenant_id=p_tenant and enabled));
 return result;
end $function$

;
create or replace function public.hub_project_revenue_statement_v1(p_tenant_id uuid,p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' as $$
declare s private.hub_project_revenue_statements;generation uuid;imported numeric;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then
  raise exception 'KPI access required' using errcode='42501';end if;
 select * into s from private.hub_project_revenue_statements where tenant_id=p_tenant_id and project_id=p_project_id
 order by observed_on desc,created_at desc limit 1;
 if not found then return null;end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 select coalesce(sum(f.amount),0) into imported from private.hub_kpi_prepared_facts f
 where f.tenant_id=p_tenant_id and f.generation_id=generation and f.kind='revenue' and f.source in('NEXT','Workify')
 and f.occurred_on<=s.observed_on and f.project in(select k.identity_value from public.hub_identity_keys k
  where k.tenant_id=p_tenant_id and k.object_id=p_project_id and k.identity_type='next_project_number' and k.confidence=1);
 answer:=jsonb_build_object('id',s.id,'observed_on',s.observed_on,'billed_total',s.billed_total,
 'imported_project_revenue',imported,'unperiodized_difference',s.billed_total-imported,'source',s.source,
 'basis','Ackumulerad fakturerad projektintäkt enligt NeXT-underlag, exklusive moms. Hela projektet till och med underlagets avläsning, oberoende av valt månadsurval. Totalsumman ersätter inte datumfördelade transaktioner och läggs inte ovanpå importerade intäkter. Avstämningsdifferensen visas separat och kan även innehålla avrundning i kontrollunderlaget. Inga månads-, års- eller betalningsbelopp ändras av detta kontrollunderlag.');
 return answer;
end $$;
revoke all on function public.hub_project_revenue_statement_v1(uuid,uuid) from public,anon;
grant execute on function public.hub_project_revenue_statement_v1(uuid,uuid) to authenticated;
