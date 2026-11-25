-- Explicit NEXT time placements confirmed against the matching Workify order lines.
create table private.hub_next_time_workify_placements (
 tenant_id uuid not null references public.hub_tenants(id),
 time_row_id uuid not null references public.kpi_import_rows(id),
 unit_id uuid not null references public.hub_objects(id),
 project_reference text not null, cost_center text not null, business_group text not null,
 registration text, workify_order text not null, workify_machine text not null,
 primary key (tenant_id,time_row_id)
);
alter table private.hub_next_time_workify_placements enable row level security;
revoke all on private.hub_next_time_workify_placements from public,anon,authenticated,service_role;

with decisions(work_date,person,hours,order_no,machine) as (values
 (date '2026-09-15','Mikael Stålberg',3,'44485','Hjullastare L120'),
 (date '2026-09-16','Mikael Stålberg',3,'44485','Hjullastare L120'),
 (date '2026-09-18','Mikael Stålberg',1,'44542','Hjullastare L120'),
 (date '2026-09-29','Fredrich Lundgren',7,'44827','Hjullastare L120'),
 (date '2026-09-30','Fredrich Lundgren',9,'44827','Hjullastare L120'),
 (date '2026-10-07','Mikael Stålberg',1,'44984','Hjullastare L120'),
 (date '2026-10-12','Mikael Stålberg',2,'45089','Hjullastare L120'),
 (date '2026-10-26','Mikael Stålberg',1.5,'45415','Hjullastare L120'),
 (date '2026-11-02','Mikael Stålberg',3.5,'45589','Hjullastare L60'),
 (date '2026-11-06','Emil Sandholm',2.5,'45612','Hjullastare L120'),
 (date '2026-11-11','Mikael Stålberg',1.5,'45731','Hjullastare L120'),
 (date '2026-11-17','Martin Nilsson',4,'45907','Traktor + Skogsvagn'),
 (date '2026-11-18','Martin Nilsson',8,'45907','Traktor + Skogsvagn'),
 (date '2026-11-17','Martin Nilsson',1.5,'45927','Maskinflytt Trailer')
)
insert into private.hub_next_time_workify_placements
select t.id,r.id,u.id,case when d.machine like 'Hjullastare%' then '1081' else '9009' end,
 case when d.machine like 'Hjullastare%' then '20' else '30' end,
 case when d.machine like 'Hjullastare%' then 'Maskiner' else 'Inhyrda lastbilar' end,
 case d.machine when 'Hjullastare L120' then 'ZLA906' when 'Hjullastare L60' then 'YKR234' end,
 d.order_no,d.machine
from decisions d join public.hub_tenants t on t.slug='elleholms'
join public.kpi_import_rows r on r.tenant_id=t.id and r.occurred_on=d.work_date and r.employee_number=d.person
 and r.paid_hours=d.hours and r.project_reference='10818' and r.data_kind='next_historical_time' and r.is_valid
join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id and b.status='completed'
join public.kpi_units u on u.tenant_id=t.id and u.enabled
 and u.name=case when d.machine like 'Hjullastare%' then 'ZLA906' else 'Inhyrda bilar' end
where exists (
 select 1 from private.hub_workify_row_observations w
 where w.tenant_id=t.id and w.source_data->>'Ordernummer'=d.order_no
  and w.source_data->>'Artikeldatum'=d.work_date::text
  and regexp_replace(btrim(w.source_data->>'Förare'),'[[:space:]]+',' ','g')=d.person
  and (w.source_data->>'Fordon'=d.machine or w.source_data->>'Artikelnamn'=d.machine)
  and replace(w.source_data->>'Kvantitet',',','.')=to_char(d.hours,'FM999990.00')
);

create function private.hub_assign_confirmed_hired_workify_v1(p_tenant uuid,p_generation uuid)
returns integer language sql set search_path to '' as $function$
 with changed as (
  update private.hub_kpi_prepared_facts f
   set unit_id=u.id,unit_name=u.name,project='9009',business_group='Inhyrda lastbilar',
    vehicle='LASTBIL',cost_center='30',cost_center_name='Transport',
    original=coalesce(f.original,'{}')||jsonb_build_object('_humla_confirmed_hired_order',jsonb_build_object('prior_unit',f.unit_name,'prior_vehicle',f.vehicle,'prior_project',f.project)),
    display_original=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_confirmed_hired_order',true)
  from public.hub_tenants t join public.kpi_units u on u.tenant_id=t.id and u.name='Inhyrda bilar' and u.enabled
  where t.slug='elleholms' and t.id=p_tenant and f.tenant_id=t.id and f.generation_id=p_generation
   and f.kind='revenue' and f.source='Workify' and f.category in ('transport','unclassified')
   and ((f.original->>'Ordernummer'='45907' and f.original->>'Artikelnummer'='13-025')
     or (f.original->>'Ordernummer'='45927' and f.original->>'Artikelnummer'='13-024'))
   and f.unit_id is distinct from u.id
  returning f.*
 ), projected as (
  update private.hub_kpi_prepared_display_facts d
  set unit_id=f.unit_id,unit_name=f.unit_name,project=f.project,business_group=f.business_group,
   vehicle=f.vehicle,cost_center=f.cost_center,original=f.display_original
  from changed f where d.tenant_id=f.tenant_id and d.generation_id=f.generation_id and d.fact_id=f.fact_id
  returning d.fact_id
 )
 select count(*)::integer from changed
$function$;
revoke all on function private.hub_assign_confirmed_hired_workify_v1(uuid,uuid) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.hub_foreman_hours_v1(p_tenant uuid, p_from date, p_to date, p_user uuid, p_unit uuid, p_months integer[], p_group text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare g uuid;months integer[]:=coalesce(p_months,array[1,2,3,4,5,6,7,8,9,10,11,12]);p_filters jsonb:='{}';centers text[];answer jsonb;
begin
-- Performs active membership, owner preview, date-range and impersonation checks.
if auth.uid() is null or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid scope or period' using errcode='22023';end if;
if not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active') or
 (p_user is not null and p_user<>auth.uid() and not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role='owner')) or
 (p_user is not null and not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=p_user and m.status='active'))
then raise exception 'Access denied' using errcode='42501';end if;
select active_generation into g from private.hub_kpi_report_state where tenant_id=p_tenant;
if g is null then raise exception 'Published report unavailable';end if;
if p_user is null and exists(select 1 from public.hub_tenant_members where tenant_id=p_tenant and user_id=auth.uid()and status='active'and role='owner')then centers:=array['30'];
else select cost_centers into centers from private.hub_foreman_access_plans where tenant_id=p_tenant and auth_user_id=coalesce(p_user,auth.uid())and status='active';end if;
 with person_keys as materialized(
 select identity_type,identity_value,(array_agg(distinct object_id))[1]person_id
 from public.hub_identity_keys where tenant_id=p_tenant and object_type='Person'
  and identity_type in('next_person_name','transpa_employee_id')and confidence=1
 group by 1,2 having count(distinct object_id)=1
 ), source_rows as materialized(
  select r.*,b.status batch_status,
   (lower(trim(coalesce(r.source_data->>'Godkänd','')))in('true','ja','1')or coalesce(r.source_data#>>'{_humla_time_approval,approved}'='true',false)) approved,
   coalesce(r.source_data,'{}')-array['Godkännandedatum','Godkänd av','Godkänd','Fakturadatum','_humla_time_approval'] fingerprint
  from private.hub_kpi_prepared_kpi_import_rows r
  join public.kpi_import_batches b on b.tenant_id=r.tenant_id and b.id=r.batch_id
  where r.tenant_id=p_tenant and r.generation_id=g and r.data_kind='next_historical_time' and b.status='completed'
   and r.occurred_on between p_from and p_to
   and extract(month from r.occurred_on)::int=any(months)
 ), occurrences as(
  select *,row_number()over(partition by batch_id,fingerprint order by row_number,id) occurrence from source_rows
 ), copies as(
  select *,row_number()over(partition by fingerprint,occurrence order by approved desc,is_valid desc,created_at desc,id) copy_rank from occurrences
 ), project_keys as materialized(
  select k.identity_value,(array_agg(distinct k.object_id))[1] object_id
  from public.hub_identity_keys k where k.tenant_id=p_tenant and k.identity_type='next_project_number'and k.confidence=1
  group by k.identity_value having count(distinct k.object_id)=1
 ), unit_members as materialized(
  select u.id unit_id,v.period,m.member
  from public.hub_objects u cross join lateral jsonb_array_elements(coalesce(u.data->'periods','[]'))v(period)
   cross join lateral jsonb_array_elements(coalesce(v.period->'members','[]'))m(member)
  where u.tenant_id=p_tenant and u.object_type='EconomicUnit'and coalesce((v.period->>'enabled')::boolean,false)
 ), resolved as materialized(
  select r.*,k.object_id project_id, a.unit_id as workify_unit,
   coalesce(a.project_reference,r.project_reference) reporting_project,
   coalesce(r.employee_object_id,pk.person_id) combined_person_id,
   coalesce(a.cost_center,nullif(trim(r.cost_center),''),nullif(trim(r.source_data->>'Kostnadsställe nr'),''),c.cost_center,'unclassified') target_center,
   coalesce(a.business_group,c.business_group) business_group,
   case when a.unit_id is not null then a.registration else coalesce(nullif(upper(trim(r.vehicle_registration)),''),case when cardinality(c.registrations)=1 then c.registrations[1]end) end registration,
   case when u.n=1 then u.unit_id end source_unit,
   coalesce(r.project_reference='99999' or lower(trim(r.source_data->>'Projektnamn'))='frånvaro',false) absence,
   upper(trim(coalesce(r.source_data->>'Tidkod','')))~'^OB' supplement,
   upper(trim(coalesce(r.source_data->>'Roll',r.description,'')))='REP' workshop
  from copies r left join private.hub_next_time_workify_placements a on a.tenant_id=r.tenant_id and a.time_row_id=r.id
  left join project_keys k on k.identity_value=coalesce(a.project_reference,r.project_reference)
  left join person_keys pk on pk.identity_type='next_person_name'and pk.identity_value=upper(trim(coalesce(r.employee_number,r.source_data->>'Namn')))
  left join lateral(
   select c.* from private.hub_kpi_prepared_kpi_project_classification_periods c
   where c.tenant_id=p_tenant and c.generation_id=g and c.project_reference=coalesce(a.project_reference,r.project_reference)
    and c.valid_from<=r.occurred_on and(c.valid_to is null or c.valid_to>=r.occurred_on)
   order by c.valid_from desc,c.id limit 1
  )c on true
  left join lateral(
   select count(distinct um.unit_id)n,(array_agg(distinct um.unit_id))[1]unit_id from unit_members um
   where um.member->>'object_id'=k.object_id::text and um.member->>'kind'='project'
    and(um.period->>'valid_from')::date<=r.occurred_on
    and(nullif(um.period->>'valid_to','')is null or(um.period->>'valid_to')::date>=r.occurred_on)
  )u on true
  where copy_rank=1
 ), collected as(
  select r.*,coalesce(r.workify_unit,case when rel.n=1 then rel.unit_id end,r.source_unit,(select (array_agg(o.id))[1]from public.hub_objects o where o.tenant_id=p_tenant and o.object_type='EconomicUnit'and o.data->>'report_fallback'='unresolved'having count(*)=1)) unit_id
  from resolved r left join lateral(
   select count(distinct a.to_object_id)n,(array_agg(distinct a.to_object_id))[1]unit_id
   from public.hub_object_relations a where a.tenant_id=p_tenant and a.from_object_id=r.source_unit
   and a.relation_type='reports_in'and a.status='active'and a.confidence=1
   and(a.valid_from is null or r.occurred_on>=(a.valid_from at time zone 'Europe/Stockholm')::date)
   and(a.valid_to is null or r.occurred_on<=(a.valid_to at time zone 'Europe/Stockholm')::date)
  )rel on true
 ), scoped as materialized(
  select * from collected r
  where(not(p_filters?'cost_center')or r.target_center=any(string_to_array(p_filters->>'cost_center',',')))
   and(not(p_filters?'project')or r.reporting_project=p_filters->>'project')
   and(not(p_filters?'unit')or r.unit_id::text=p_filters->>'unit' or p_filters->>'unit'='vehicle:'||r.registration)
   and(not(p_filters?'vehicle')or r.registration=p_filters->>'vehicle')
   and(not(p_filters?'group')or r.business_group=any(string_to_array(p_filters->>'group',',')))
   and not exists(select 1 from private.hub_kpi_project_exclusions e where e.tenant_id=p_tenant and e.enabled
    and(e.project_id=r.project_id or e.economic_unit_id=r.source_unit))
 ), native_days as materialized(
  select coalesce(t.person_object_id,k.person_id)person_id,t.work_date,sum(t.work_hours)hours
  from private.hub_kpi_prepared_kpi_transpa_time_facts t
  left join person_keys k on k.identity_type='transpa_employee_id'and k.identity_value=t.employee_id
  where t.tenant_id=p_tenant and t.generation_id=g and t.work_hours>0
   and t.work_date between p_from and p_to
   and extract(month from t.work_date)::int=any(months)
  group by 1,2
 ), next_days as materialized(
  select combined_person_id,coalesce(combined_person_id::text,nullif(employee_number,''),source_data->>'Namn',id::text)person_label,occurred_on,sum(paid_hours)hours
  from collected where approved and is_valid and paid_hours>=0 and not absence and not supplement and not workshop group by 1,2,3
 ), valid_work as materialized(
  select r.*,case when r.workshop then 0 else r.paid_hours*greatest(d.hours-coalesce(n.hours,0),0)/nullif(d.hours,0)end net_project_hours
  from scoped r left join next_days d on d.combined_person_id is not distinct from r.combined_person_id
   and d.person_label=coalesce(r.combined_person_id::text,nullif(r.employee_number,''),r.source_data->>'Namn',r.id::text)and d.occurred_on=r.occurred_on
  left join native_days n on n.person_id=r.combined_person_id and n.work_date=r.occurred_on
  where r.approved and r.is_valid and r.paid_hours>=0 and not r.absence and not r.supplement
 ),
scoped_finance as materialized(
select f.* from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user)f where extract(month from f.occurred_on)::int=any(months)
and(p_unit is null or f.unit_id=p_unit)and(p_group is null or coalesce(nullif(f.business_group,''),'Ej klassificerat')=p_group)
),
saw_links as materialized(
select distinct f.unit_id saw_unit,f.occurred_on work_date,(f.original#>>'{_humla_saw_activity,original_unit_id}')::uuid truck_unit
from scoped_finance f
where f.kind='revenue'and f.original#>>'{_humla_saw_activity,branch}'='saw'and f.original#>>'{_humla_saw_activity,reason}'='article_hour_split'
and f.original#>>'{_humla_saw_activity,original_unit_id}'is not null
and extract(month from f.occurred_on)::int=any(months)
and(p_unit is null or f.unit_id=p_unit)and(p_group is null or coalesce(nullif(f.business_group,''),'Ej klassificerat')=p_group)
),
visible_next as materialized(
select r.* from valid_work r where not workshop and net_project_hours>0
and ((centers is not null and r.target_center=any(centers))or(centers is null and exists(select 1 from public.hub_transport_leader_units a where a.tenant_id=p_tenant and a.user_id=coalesce(p_user,auth.uid())and a.unit_id=r.unit_id and a.valid_from<=r.occurred_on and(a.valid_to is null or a.valid_to>=r.occurred_on))))
and(p_unit is null or r.unit_id=p_unit)
and(p_group is null or p_group=coalesce((select bg.name from public.hub_objects u cross join lateral jsonb_array_elements(u.data->'periods')v(period)join public.kpi_business_groups bg on bg.tenant_id=u.tenant_id and bg.id::text=(v.period->>'business_group_id')where u.tenant_id=p_tenant and u.id=r.unit_id and(v.period->>'valid_from')::date<=r.occurred_on and(v.period->>'valid_to'is null or(v.period->>'valid_to')::date>=r.occurred_on)limit 1),r.business_group))
),
native_links as materialized(
select original->>'time_report_id'id,(array_agg(distinct unit_id))[1]unit_id,count(distinct unit_id)=1 and bool_and(unit_id is not null)unambiguous
from private.hub_kpi_prepared_display_facts where tenant_id=p_tenant and generation_id=g and source='TransPA'and category='personnel'and original->>'time_report_id'is not null
group by 1
),
visible_native as materialized(
select l.id,l.unit_id,min(t.work_date)work_date,min(t.work_hours)hours
from native_links l join private.hub_kpi_prepared_kpi_transpa_time_facts t on t.tenant_id=p_tenant and t.generation_id=g and t.time_report_id=l.id
where l.unambiguous and t.work_date between p_from and p_to and extract(month from t.work_date)::int=any(months)
and(exists(select 1 from scoped_finance f where f.source='TransPA'and f.category='personnel'and f.original->>'time_report_id'=l.id)
or exists(select 1 from saw_links s where s.truck_unit=l.unit_id and s.work_date=t.work_date))
group by l.id,l.unit_id having min(t.work_hours)=max(t.work_hours)and min(t.work_hours)>0 and min(t.work_date)=max(t.work_date)
),
shared_next as(
select r.* from valid_work r where not r.workshop and r.net_project_hours>0
and exists(select 1 from saw_links s where s.truck_unit=r.unit_id and s.work_date=r.occurred_on)
and not exists(select 1 from visible_next n where n.id=r.id)
),
time_rows as(
select 'TransPA:'||n.id id,
case when exists(select 1 from scoped_finance f where f.source='TransPA'and f.original->>'time_report_id'=n.id)then n.unit_id
else coalesce((select min(s.saw_unit::text)::uuid from saw_links s where s.truck_unit=n.unit_id and s.work_date=n.work_date),n.unit_id)end unit_id,
n.work_date,n.hours,'TransPA' source from visible_native n
union all select 'NEXT:'||id,unit_id,occurred_on,net_project_hours,'NEXT'from visible_next
union all select 'NEXT:'||r.id,coalesce((select min(s.saw_unit::text)::uuid from saw_links s where s.truck_unit=r.unit_id and s.work_date=r.occurred_on),r.unit_id),r.occurred_on,r.net_project_hours,'NEXT'from shared_next r
),
u as(select unit_id,sum(hours)hours from time_rows group by 1)
select jsonb_build_object('worked_hours',(select sum(hours)from time_rows),'transpa_hours',(select sum(hours)from time_rows where source='TransPA'),
'next_hours',(select sum(hours)from time_rows where source='NEXT'),'through',(select max(work_date)from time_rows),
'transpa_through',(select max(work_date)from time_rows where source='TransPA'),'next_through',(select max(work_date)from time_rows where source='NEXT'),
'shared_crane_time',exists(select 1 from saw_links),
'covered_units',(select count(*)from u where unit_id is not null),'units',coalesce((select jsonb_agg(to_jsonb(u))from u),'[]'),
'basis','Registrerad arbetstid: TransPA plus godkänd NEXT-projekttid efter avräkning av överlapp per person och dag. Frånvaro, OB och verkstadstid ingår inte. Saknade timmar uppskattas inte.')into answer;
return answer;
end $function$
;

CREATE OR REPLACE FUNCTION private.hub_kpi_next_time_period_v1(p_tenant uuid, p_year integer, p_months integer[], p_filters jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET jit TO 'off'
 SET enable_nestloop TO 'on'
 SET work_mem TO '64MB'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare g uuid;months integer[];answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read')then raise exception 'KPI access required'using errcode='42501';end if;
 months:=private.hub_kpi_month_scope_v1(p_year,p_months);
 g:=private.hub_kpi_active_report_generation_v1(p_tenant);
 if not exists(select 1 from private.hub_kpi_prepared_kpi_import_rows r where r.tenant_id=p_tenant and r.generation_id=g
  and r.data_kind='next_historical_time'and r.occurred_on between greatest(make_date(p_year,9,1),nullif(p_filters->>'date_from','')::date)and least(make_date(p_year+1,8,31),nullif(p_filters->>'date_to','')::date)
  and extract(month from r.occurred_on)::int=any(months))then
  return jsonb_build_object('available',false,'rows',0,'project_hours',null,'workshop_hours',null,'absence_hours',0,'supplement_hours',0,
   'review_rows',0,'unmapped_unit_hours',0,'workshop_hours_without_cost_reference',0,'workshop_cost_references','[]'::jsonb,'units','[]'::jsonb,
   'basis','Publicerad NEXT-tid saknas för perioden. Saknat underlag visas inte som noll arbetade timmar.');
 end if;

 with person_keys as materialized(
 select identity_type,identity_value,(array_agg(distinct object_id))[1]person_id
 from public.hub_identity_keys where tenant_id=p_tenant and object_type='Person'
  and identity_type in('next_person_name','transpa_employee_id')and confidence=1
 group by 1,2 having count(distinct object_id)=1
 ), repair_facts as materialized(
 select * from private.hub_kpi_prepared_month_facts_v1(p_tenant,p_year,p_months,p_filters)
 where kind='cost'and category='service_repair'
 ), source_rows as materialized(
  select r.*,b.status batch_status,
   (lower(trim(coalesce(r.source_data->>'Godkänd','')))in('true','ja','1')or coalesce(r.source_data#>>'{_humla_time_approval,approved}'='true',false)) approved,
   coalesce(r.source_data,'{}')-array['Godkännandedatum','Godkänd av','Godkänd','Fakturadatum','_humla_time_approval'] fingerprint
  from private.hub_kpi_prepared_kpi_import_rows r
  join public.kpi_import_batches b on b.tenant_id=r.tenant_id and b.id=r.batch_id
  where r.tenant_id=p_tenant and r.generation_id=g and r.data_kind='next_historical_time' and b.status='completed'
   and r.occurred_on between greatest(make_date(p_year,9,1),nullif(p_filters->>'date_from','')::date)and least(make_date(p_year+1,8,31),nullif(p_filters->>'date_to','')::date)
   and extract(month from r.occurred_on)::int=any(months)
 ), occurrences as(
  select *,row_number()over(partition by batch_id,fingerprint order by row_number,id) occurrence from source_rows
 ), copies as(
  select *,row_number()over(partition by fingerprint,occurrence order by approved desc,is_valid desc,created_at desc,id) copy_rank from occurrences
 ), project_keys as materialized(
  select k.identity_value,(array_agg(distinct k.object_id))[1] object_id
  from public.hub_identity_keys k where k.tenant_id=p_tenant and k.identity_type='next_project_number'and k.confidence=1
  group by k.identity_value having count(distinct k.object_id)=1
 ), unit_members as materialized(
  select u.id unit_id,v.period,m.member
  from public.hub_objects u cross join lateral jsonb_array_elements(coalesce(u.data->'periods','[]'))v(period)
   cross join lateral jsonb_array_elements(coalesce(v.period->'members','[]'))m(member)
  where u.tenant_id=p_tenant and u.object_type='EconomicUnit'and coalesce((v.period->>'enabled')::boolean,false)
 ), resolved as materialized(
  select r.*,k.object_id project_id, a.unit_id as workify_unit,
   coalesce(a.project_reference,r.project_reference) reporting_project,
   coalesce(r.employee_object_id,pk.person_id) combined_person_id,
   coalesce(a.cost_center,nullif(trim(r.cost_center),''),nullif(trim(r.source_data->>'Kostnadsställe nr'),''),c.cost_center,'unclassified') target_center,
   coalesce(a.business_group,c.business_group) business_group,
   case when a.unit_id is not null then a.registration else coalesce(nullif(upper(trim(r.vehicle_registration)),''),case when cardinality(c.registrations)=1 then c.registrations[1]end) end registration,
   case when u.n=1 then u.unit_id end source_unit,
   coalesce(r.project_reference='99999' or lower(trim(r.source_data->>'Projektnamn'))='frånvaro',false) absence,
   upper(trim(coalesce(r.source_data->>'Tidkod','')))~'^OB' supplement,
   upper(trim(coalesce(r.source_data->>'Roll',r.description,'')))='REP' workshop
  from copies r left join private.hub_next_time_workify_placements a on a.tenant_id=r.tenant_id and a.time_row_id=r.id
  left join project_keys k on k.identity_value=coalesce(a.project_reference,r.project_reference)
  left join person_keys pk on pk.identity_type='next_person_name'and pk.identity_value=upper(trim(coalesce(r.employee_number,r.source_data->>'Namn')))
  left join lateral(
   select c.* from private.hub_kpi_prepared_kpi_project_classification_periods c
   where c.tenant_id=p_tenant and c.generation_id=g and c.project_reference=coalesce(a.project_reference,r.project_reference)
    and c.valid_from<=r.occurred_on and(c.valid_to is null or c.valid_to>=r.occurred_on)
   order by c.valid_from desc,c.id limit 1
  )c on true
  left join lateral(
   select count(distinct um.unit_id)n,(array_agg(distinct um.unit_id))[1]unit_id from unit_members um
   where um.member->>'object_id'=k.object_id::text and um.member->>'kind'='project'
    and(um.period->>'valid_from')::date<=r.occurred_on
    and(nullif(um.period->>'valid_to','')is null or(um.period->>'valid_to')::date>=r.occurred_on)
  )u on true
  where copy_rank=1
 ), collected as(
  select r.*,coalesce(r.workify_unit,case when rel.n=1 then rel.unit_id end,r.source_unit,(select (array_agg(o.id))[1]from public.hub_objects o where o.tenant_id=p_tenant and o.object_type='EconomicUnit'and o.data->>'report_fallback'='unresolved'having count(*)=1)) unit_id
  from resolved r left join lateral(
   select count(distinct a.to_object_id)n,(array_agg(distinct a.to_object_id))[1]unit_id
   from public.hub_object_relations a where a.tenant_id=p_tenant and a.from_object_id=r.source_unit
   and a.relation_type='reports_in'and a.status='active'and a.confidence=1
   and(a.valid_from is null or r.occurred_on>=(a.valid_from at time zone 'Europe/Stockholm')::date)
   and(a.valid_to is null or r.occurred_on<=(a.valid_to at time zone 'Europe/Stockholm')::date)
  )rel on true
 ), scoped as materialized(
  select * from collected r
  where(not(p_filters?'cost_center')or r.target_center=any(string_to_array(p_filters->>'cost_center',',')))
   and(not(p_filters?'project')or r.reporting_project=p_filters->>'project')
   and(not(p_filters?'unit')or r.unit_id::text=p_filters->>'unit' or p_filters->>'unit'='vehicle:'||r.registration)
   and(not(p_filters?'vehicle')or r.registration=p_filters->>'vehicle')
   and(not(p_filters?'group')or r.business_group=any(string_to_array(p_filters->>'group',',')))
   and not exists(select 1 from private.hub_kpi_project_exclusions e where e.tenant_id=p_tenant and e.enabled
    and(e.project_id=r.project_id or e.economic_unit_id=r.source_unit))
 ), native_days as materialized(
  select coalesce(t.person_object_id,k.person_id)person_id,t.work_date,sum(t.work_hours)hours
  from private.hub_kpi_prepared_kpi_transpa_time_facts t
  left join person_keys k on k.identity_type='transpa_employee_id'and k.identity_value=t.employee_id
  where t.tenant_id=p_tenant and t.generation_id=g and t.work_hours>0
   and t.work_date between greatest(make_date(p_year,9,1),nullif(p_filters->>'date_from','')::date)and least(make_date(p_year+1,8,31),nullif(p_filters->>'date_to','')::date)
   and extract(month from t.work_date)::int=any(months)
  group by 1,2
 ), next_days as materialized(
  select combined_person_id,coalesce(combined_person_id::text,nullif(employee_number,''),source_data->>'Namn',id::text)person_label,occurred_on,sum(paid_hours)hours
  from collected where approved and is_valid and paid_hours>=0 and not absence and not supplement and not workshop group by 1,2,3
 ), valid_work as materialized(
  select r.*,case when r.workshop then 0 else r.paid_hours*greatest(d.hours-coalesce(n.hours,0),0)/nullif(d.hours,0)end net_project_hours
  from scoped r left join next_days d on d.combined_person_id is not distinct from r.combined_person_id
   and d.person_label=coalesce(r.combined_person_id::text,nullif(r.employee_number,''),r.source_data->>'Namn',r.id::text)and d.occurred_on=r.occurred_on
  left join native_days n on n.person_id=r.combined_person_id and n.work_date=r.occurred_on
  where r.approved and r.is_valid and r.paid_hours>=0 and not r.absence and not r.supplement
 ), repair_projects as(
  select project_reference project,project_id,date_trunc('month',occurred_on)::date month_start,sum(paid_hours)hours
  from valid_work where workshop group by 1,2,3
 ), repair_debits as(
  select f.project,date_trunc('month',f.occurred_on)::date month_start,sum(f.amount)amount,count(*)rows
  from repair_facts f
  where f.source='NEXT'and f.kind='cost'and f.category='service_repair'and f.account='4630'
   and(concat_ws(' ',f.description,f.original->>'Verifikationstext')ilike '%verkstad%'or f.original->>'Verifikation nr'~'^AO[.][0-9]{4}-[0-9]{2}$')
  group by 1,2
 ), estimates as(
 select f.project,date_trunc('month',f.occurred_on)::date month_start,sum(f.amount) estimated_repair_cost
 from repair_facts f
 where f.kind='cost'and f.category='service_repair'and f.source='Verkstadsschablon'group by 1,2
 ), repair_evidence as(
  select p.*,d.amount posted_repair_debit,coalesce(d.rows,0)cost_rows,e.estimated_repair_cost from repair_projects p left join repair_debits d using(project,month_start)left join estimates e using(project,month_start)
 ), units as(
  select unit_id,sum(net_project_hours)net_project_hours,sum(paid_hours)filter(where not workshop)project_hours,sum(paid_hours)filter(where workshop)workshop_hours
  from valid_work where unit_id is not null group by unit_id
 )select jsonb_build_object('available',exists(select 1 from scoped),'rows',(select count(*)from valid_work),
  'net_project_hours',(select sum(net_project_hours)from valid_work),
  'overlap_hours',(select coalesce(sum(paid_hours-net_project_hours)filter(where not workshop),0)from valid_work),
  'vehicles',coalesce((select jsonb_agg(to_jsonb(v))from(
   select registration vehicle,unit_id::text unit_key,sum(net_project_hours)hours from valid_work
   where not workshop and registration~'^[A-Z]{3}[0-9]{2}[A-Z0-9]$'group by 1,2)v),'[]'::jsonb),
  'project_hours',case when exists(select 1 from scoped)then coalesce((select sum(paid_hours)from valid_work where not workshop),0)end,
  'workshop_hours',case when exists(select 1 from scoped)then coalesce((select sum(paid_hours)from valid_work where workshop),0)end,
  'absence_hours',(select coalesce(sum(paid_hours),0)from scoped where approved and is_valid and absence),
  'supplement_hours',(select coalesce(sum(paid_hours),0)from scoped where approved and is_valid and not absence and supplement),
  'review_rows',(select count(*)from scoped where not approved or not is_valid or paid_hours is null or paid_hours<0),
  'unmapped_unit_hours',(select coalesce(sum(paid_hours),0)from valid_work where source_unit is null),
  'workshop_hours_without_cost_reference',(select coalesce(sum(hours),0)from repair_evidence where cost_rows=0),
  'workshop_estimated_repair_cost',(select coalesce(sum(estimated_repair_cost),0)from repair_evidence),
  'workshop_cost_references',coalesce((select jsonb_agg(to_jsonb(e)order by e.month_start,e.project)from repair_evidence e),'[]'::jsonb),
  'units',coalesce((select jsonb_agg(jsonb_build_object('key',unit_id,'project_hours',coalesce(project_hours,0),'net_project_hours',coalesce(net_project_hours,0),'workshop_hours',coalesce(workshop_hours,0)))from units),'[]'::jsonb),
  'basis','Godkända NEXT-tidrader på mottagande kostnadsställe/projekt. Frånvaro och OB-tillägg ingår inte i arbetad tid. Identiska återimporter räknas en gång; upprepade poster i samma fil behålls. Projekttid kompletterar TransPA efter avräkning av överlapp på identifierad person och dag. Verkstadstid visas separat och räknas inte som fordonsbeläggning. Verkstadstid hör till Service & reparation; befintlig NEXT-verkstadsdebitering räknas endast en gång. Endast godkända kostnadsprofiler skapar preliminär schablonkostnad för tid utan verkstadsdebitering. Den ersätts när verklig NEXT-debitering finns. Historik 2025/26: 33 000 kr i månadslön enligt godkänd schablon, endast tid utöver TransPA kostnadssätts. Motsvarande NEXT-arbetskostnad räknas av inom projekt/månad; ej täckt kostnad ligger kvar. Historisk arbetstid saknar rolluppgift och visas som projekttid; ingen verkstadsroll antas från personens namn.')into answer;
 return answer;
end $function$
;

CREATE OR REPLACE FUNCTION private.hub_apply_workify_article_units_v1(p_tenant uuid, p_generation uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare r record;t record;n integer:=0;before_count bigint;before_amount numeric;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then raise exception 'KPI management required';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant)then raise exception 'Generation tenant mismatch';end if;
 select count(*),sum(amount) into before_count,before_amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 for r in select f.*,a.id rule_id,a.target_unit_id from private.hub_kpi_prepared_facts f
 join private.hub_workify_article_unit_rules a on a.tenant_id=f.tenant_id and a.enabled and f.occurred_on>=a.valid_from and (a.valid_to is null or f.occurred_on<=a.valid_to)
 and strpos(lower(coalesce(nullif(f.original->>'Artikelnamn',''),f.description,'')),lower(trim(a.article_contains)))>0
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.source='Workify' and f.kind='revenue'
 loop
  if exists(select 1 from private.hub_workify_article_unit_rules a where a.tenant_id=p_tenant and a.enabled and a.id<>r.rule_id and a.target_unit_id<>r.target_unit_id
   and r.occurred_on>=a.valid_from and (a.valid_to is null or r.occurred_on<=a.valid_to)
   and strpos(lower(coalesce(nullif(r.original->>'Artikelnamn',''),r.description,'')),lower(trim(a.article_contains)))>0)then raise exception 'Conflicting article routing requires review';end if;
  select u.id,p.payload->>'name' name,p.payload->>'main_vehicle' vehicle,p.payload->'projects'->>0 project,g.name grp,
   pc.cost_center,pc.cost_center_name into strict t
  from public.kpi_units u join public.hub_objects h on h.id=u.id and h.tenant_id=u.tenant_id and h.object_type='EconomicUnit'
  join public.kpi_unit_periods p on p.unit_id=u.id and p.tenant_id=u.tenant_id and p.valid_from<=r.occurred_on and (p.valid_to is null or p.valid_to>=r.occurred_on)
  join public.kpi_business_groups g on g.id::text=p.payload->>'business_group_id' and g.tenant_id=u.tenant_id and g.enabled
  join public.kpi_project_classification_periods pc on pc.tenant_id=u.tenant_id and pc.project_reference=p.payload->'projects'->>0 and pc.valid_from<=r.occurred_on and (pc.valid_to is null or pc.valid_to>=r.occurred_on)
  where u.tenant_id=p_tenant and u.id=r.target_unit_id and (p.payload->>'enabled')::boolean;
  if t.vehicle is null or t.project is null then raise exception 'Article target lacks confirmed vehicle/project';end if;
  if row(r.unit_id,r.vehicle,r.project,r.cost_center,r.business_group) is not distinct from row(t.id,t.vehicle,t.project,t.cost_center,t.grp)then continue;end if;
  insert into private.hub_article_unit_routing_audit(tenant_id,generation_id,fact_id,rule_id,before_record,after_record,actor)
  values(p_tenant,p_generation,r.fact_id,r.rule_id,to_jsonb(r),jsonb_build_object('unit_id',t.id,'vehicle',t.vehicle,'project',t.project,'cost_center',t.cost_center,'business_group',t.grp),auth.uid()) on conflict do nothing;
  update private.hub_kpi_prepared_facts set unit_id=t.id,unit_name=t.name,vehicle=t.vehicle,project=t.project,cost_center=t.cost_center,cost_center_name=t.cost_center_name,business_group=t.grp,
   classification_source=coalesce(classification_source,'{}')||jsonb_build_object('article_unit_rule',r.rule_id,'reason','confirmed_article_unit_rule'),
   display_original=display_original||jsonb_build_object('_humla_article_unit_rule',r.rule_id)
  where tenant_id=p_tenant and generation_id=p_generation and fact_id=r.fact_id;
  update private.hub_kpi_prepared_display_facts set unit_id=t.id,unit_name=t.name,vehicle=t.vehicle,project=t.project,cost_center=t.cost_center,business_group=t.grp,
   original=original||jsonb_build_object('_humla_article_unit_rule',r.rule_id)
  where tenant_id=p_tenant and generation_id=p_generation and fact_id=r.fact_id;
  n:=n+1;
 end loop;
 if row(before_count,before_amount) is distinct from (select row(count(*),sum(amount))from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation)then raise exception 'Article routing changed financial totals';end if;
 return n+private.hub_assign_confirmed_hired_workify_v1(p_tenant,p_generation);
end $function$
;

do $migration$
declare r record;
begin
 perform pg_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0));
 for r in select s.tenant_id,s.active_generation from private.hub_kpi_report_state s
 join public.hub_tenants t on t.id=s.tenant_id and t.slug='elleholms' where s.active_generation is not null loop
  if (select count(*) from private.hub_next_time_workify_placements where tenant_id=r.tenant_id)<>14
   then raise exception 'Workify time evidence did not resolve to 14 unique rows';end if;
  perform private.hub_assign_confirmed_hired_workify_v1(r.tenant_id,r.active_generation);
  perform private.hub_validate_report_projection_v1(r.tenant_id,r.active_generation);
  update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=r.tenant_id;
 end loop;
end $migration$;
