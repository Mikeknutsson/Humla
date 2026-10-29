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
perform 1 from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user)limit 1;
select active_generation into g from private.hub_kpi_report_state where tenant_id=p_tenant;
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
  select r.*,k.object_id project_id,
   coalesce(r.employee_object_id,pk.person_id) combined_person_id,
   coalesce(nullif(trim(r.cost_center),''),nullif(trim(r.source_data->>'Kostnadsställe nr'),''),c.cost_center,'unclassified') target_center,
   c.business_group,
   coalesce(nullif(upper(trim(r.vehicle_registration)),''),case when cardinality(c.registrations)=1 then c.registrations[1]end) registration,
   case when u.n=1 then u.unit_id end source_unit,
   coalesce(r.project_reference='99999' or lower(trim(r.source_data->>'Projektnamn'))='frånvaro',false) absence,
   upper(trim(coalesce(r.source_data->>'Tidkod','')))~'^OB' supplement,
   upper(trim(coalesce(r.source_data->>'Roll',r.description,'')))='REP' workshop
  from copies r left join project_keys k on k.identity_value=r.project_reference
  left join person_keys pk on pk.identity_type='next_person_name'and pk.identity_value=upper(trim(coalesce(r.employee_number,r.source_data->>'Namn')))
  left join lateral(
   select c.* from private.hub_kpi_prepared_kpi_project_classification_periods c
   where c.tenant_id=p_tenant and c.generation_id=g and c.project_reference=r.project_reference
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
  select r.*,coalesce(case when rel.n=1 then rel.unit_id end,r.source_unit,(select (array_agg(o.id))[1]from public.hub_objects o where o.tenant_id=p_tenant and o.object_type='EconomicUnit'and o.data->>'report_fallback'='unresolved'having count(*)=1)) unit_id
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
   and(not(p_filters?'project')or r.project_reference=p_filters->>'project')
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
saw_links as materialized(
select distinct f.unit_id saw_unit,f.occurred_on work_date,(f.original#>>'{_humla_saw_activity,original_unit_id}')::uuid truck_unit
from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user)f
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
scoped_finance as materialized(
select f.* from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user)f where extract(month from f.occurred_on)::int=any(months)
and(p_unit is null or f.unit_id=p_unit)and(p_group is null or coalesce(nullif(f.business_group,''),'Ej klassificerat')=p_group)
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
do $migration$
declare d text;
begin
select pg_get_functiondef('public.hub_transport_leader_scorecard_v4(uuid,date,date,uuid,uuid,integer,integer[],text)'::regprocedure)into d;
d:=replace(d,$old$time_to:=least((time_basis->>'transpa_through')::date,(time_basis->>'next_through')::date);$old$,$new$time_to:=case when(time_basis->>'shared_crane_time')::boolean then(time_basis->>'through')::date else least((time_basis->>'transpa_through')::date,(time_basis->>'next_through')::date)end;$new$);
execute d;
end $migration$;