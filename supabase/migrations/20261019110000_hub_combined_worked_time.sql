-- Shared approved NEXT time supplements TransPA after person/day overlap.
CREATE OR REPLACE FUNCTION private.hub_kpi_next_time_period_v1(p_tenant uuid, p_year integer, p_months integer[], p_filters jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET jit TO 'off'
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

 with source_rows as materialized(
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
  left join lateral(select (array_agg(distinct object_id))[1]person_id from public.hub_identity_keys
   where tenant_id=p_tenant and object_type='Person'and identity_type='next_person_name'and confidence=1
    and identity_value=upper(trim(coalesce(r.employee_number,r.source_data->>'Namn')))
   having count(distinct object_id)=1)pk on true
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
  left join lateral(select (array_agg(distinct object_id))[1]person_id from public.hub_identity_keys
   where tenant_id=p_tenant and object_type='Person'and identity_type='transpa_employee_id'and confidence=1
    and identity_value=t.employee_id having count(distinct object_id)=1)k on true
  where t.tenant_id=p_tenant and t.generation_id=g and t.work_hours>0
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
  from private.hub_kpi_prepared_month_facts_v1(p_tenant,p_year,p_months,p_filters)f
  where f.source='NEXT'and f.kind='cost'and f.category='service_repair'and f.account='4630'
   and(concat_ws(' ',f.description,f.original->>'Verifikationstext')ilike '%verkstad%'or f.original->>'Verifikation nr'~'^AO[.][0-9]{4}-[0-9]{2}$')
  group by 1,2
 ), estimates as(
 select f.project,date_trunc('month',f.occurred_on)::date month_start,sum(f.amount) estimated_repair_cost
 from private.hub_kpi_prepared_month_facts_v1(p_tenant,p_year,p_months,p_filters)f
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
end $function$;
