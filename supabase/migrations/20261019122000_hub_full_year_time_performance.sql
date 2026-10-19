-- Reuse person identities and financial repair facts instead of row-by-row lookups.
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
end $function$;
-- Aggregate vehicle categories once for the selected scope.
CREATE OR REPLACE FUNCTION private.hub_kpi_prepared_snapshot_v1(p_tenant_id uuid, p_fiscal_year integer, p_selected_months integer[], p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET work_mem TO '64MB'
 SET enable_nestloop TO 'off'
 SET jit TO 'off'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare report_generation uuid:=private.hub_kpi_active_report_generation_v1(p_tenant_id); output jsonb; months integer[]; fy_from date; fy_to date;selected_from date;selected_to date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501'; end if;
 if not exists(select 1 from private.hub_kpi_report_generations g where g.id=report_generation and p_fiscal_year between g.first_fiscal_year and g.last_fiscal_year) then raise exception 'Fiscal year outside prepared report coverage' using errcode='55000';end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);
 fy_from:=greatest(make_date(p_fiscal_year,9,1),nullif(p_filters->>'date_from','')::date);
 fy_to:=least(make_date(p_fiscal_year+1,8,31),nullif(p_filters->>'date_to','')::date);
 select min(make_date(p_fiscal_year+case when m<9 then 1 else 0 end,m,1)),
  (max(make_date(p_fiscal_year+case when m<9 then 1 else 0 end,m,1))+interval '1 month - 1 day')::date
 into selected_from,selected_to from unnest(months)m;

 with selected_facts as materialized(select fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,jsonb_build_object('_humla_material_separation',original->'_humla_material_separation','_humla_fuel',original->'_humla_fuel','time_report_id',original->'time_report_id','_humla_distribution',jsonb_build_object('status',original#>'{_humla_distribution,status}')) original from private.hub_kpi_report_display_facts_v1 f
 where f.generation_id=report_generation and f.tenant_id=p_tenant_id and f.fiscal_year=p_fiscal_year and f.occurred_on between selected_from and selected_to
 and extract(month from f.occurred_on)::int=any(months)
 and (not(p_filters?'group') or f.business_group=any(string_to_array(p_filters->>'group',',')))
 and (not(p_filters?'unit') or coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=p_filters->>'unit')
 and (not(p_filters?'vehicle') or coalesce(f.vehicle,'unassigned')=p_filters->>'vehicle')
 and (not(p_filters?'project') or coalesce(f.project,'unassigned')=p_filters->>'project')
 and (not(p_filters?'category') or f.category=p_filters->>'category')
 and (not(p_filters?'kind') or f.kind=p_filters->>'kind')
 and (not(p_filters?'source') or f.source=p_filters->>'source')
 and (not(p_filters?'date_from') or f.occurred_on>=(p_filters->>'date_from')::date)
 and (not(p_filters?'date_to') or f.occurred_on<=(p_filters->>'date_to')::date)),
 facts as materialized(select * from selected_facts where not(p_filters?'cost_center') or cost_center=any(string_to_array(p_filters->>'cost_center',','))),
 month_dates as(select m,make_date(case when m>=9 then p_fiscal_year else p_fiscal_year+1 end,m,1) dt from unnest(months) m),
 monthly as(select m,dt,coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost,count(f.fact_id) rows from month_dates left join facts f on date_trunc('month',f.occurred_on)::date=dt group by m,dt),
 cats as(select category,round(sum(amount),2) amount from facts where kind='cost' group by category),
 totals as(select coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost,
 coalesce(sum(amount) filter(where kind='revenue' and vehicle='LASTBIL'),0) hired,
 count(distinct vehicle) filter(where kind='revenue' and amount<>0 and vehicle not in ('LASTBIL','Ej fördelat')) vehicles from facts),
 groups as(select business_group key,business_group label,count(*) rows,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by business_group),
 units as(select coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') key,max(coalesce(unit_name,vehicle,'Ej fördelat')) label,count(*) rows,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by 1),
 unit_children as materialized(select coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') unit_key,case when original#>>'{_humla_distribution,status}'='allocated' then 'shared:'||project else coalesce(vehicle,'project:'||project,'unassigned') end key,max(case when original#>>'{_humla_distribution,status}'='allocated' then 'Gemensam kostnad · '||project else coalesce(vehicle,project,'Ej fördelat') end) label,max(case when original#>>'{_humla_distribution,status}'<>'allocated' or original#>>'{_humla_distribution,status}' is null then vehicle end) vehicle,max(project) project,count(*) rows,round(coalesce(sum(amount)filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount)filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by 1,2),
 all_daily as materialized(select * from private.hub_kpi_prepared_daily_v1(p_tenant_id,date '2000-01-01',fy_to)),
 first_seen as(select vehicle_id,min(work_date) first_seen from all_daily group by vehicle_id),
 daily as materialized(select d.*,upper(trim(split_part(vehicle_name,' ',1))) reg from all_daily d
 where d.work_date between fy_from and fy_to and extract(month from d.work_date)::int=any(months)
 and upper(trim(split_part(vehicle_name,' ',1)))~'^[A-Z]{3}[0-9]{2}[A-Z0-9]$'
 and ((p_filters-array['date_from','date_to'])='{}'::jsonb or (d.work_date,upper(trim(split_part(d.vehicle_name,' ',1)))) in(select f.occurred_on,f.vehicle from facts f where f.source='TransPA'))),
 vehicle_time_base as(select d.vehicle_id,max(d.reg) vehicle,sum(d.reported_vehicle_hours)::numeric hours,sum(d.time_reports) time_reports,min(fs.first_seen) first_seen from daily d join first_seen fs using(vehicle_id) group by d.vehicle_id),
 vehicle_time as(select v.*,(select count(*)::numeric from generate_series(greatest(fy_from,v.first_seen),fy_to,interval '1 day') d where extract(month from d)::int=any(months) and extract(isodow from d) between 1 and 5 and not public.hub_is_swedish_public_holiday(d::date)
 and ((p_filters-array['date_from','date_to'])='{}'::jsonb or exists(select 1 from (select id,tenant_id,project_reference,project_name,cost_center,cost_center_name,business_group,registrations,valid_from,valid_to,source,created_at from private.hub_kpi_prepared_kpi_project_classification_periods where generation_id=report_generation) r where r.tenant_id=p_tenant_id and v.vehicle=any(r.registrations) and r.valid_from<=d::date and (r.valid_to is null or r.valid_to>=d::date) and (not(p_filters?'cost_center') or r.cost_center=any(string_to_array(p_filters->>'cost_center',','))) and (not(p_filters?'group') or r.business_group=any(string_to_array(p_filters->>'group',',')))))) * coalesce((select s.vehicle_capacity_hours_per_day::numeric from (select tenant_id,currency,timezone,financial_year_start_month,financial_year_start_day,vehicle_capacity_hours_per_day,updated_by,created_at,updated_at from private.hub_kpi_prepared_kpi_settings where generation_id=report_generation) s where s.tenant_id=p_tenant_id),8) available_hours from vehicle_time_base v),
 time_totals as(select coalesce(sum(hours),0) hours,coalesce(sum(available_hours),0) available,count(*) vehicles from vehicle_time),
 next_daily as(select n.occurred_on work_date,upper(trim(n.vehicle_registration)) vehicle,sum(n.paid_hours) hours from (select id,tenant_id,batch_id,row_number,data_kind,occurred_on,vehicle_object_id,vehicle_registration,employee_object_id,employee_number,project_reference,cost_center,account,description,quantity,amount,currency,available_hours,occupied_hours,paid_hours,billable_hours,is_valid,validation_errors,source_data,created_at,allocation,source_system,external_transaction_id,source_fingerprint from private.hub_kpi_prepared_kpi_import_rows where generation_id=report_generation) n where n.tenant_id=p_tenant_id and n.is_valid and n.data_kind='next_historical_time' and n.occurred_on between fy_from and fy_to and extract(month from n.occurred_on)::int=any(months)
 and upper(trim(coalesce(n.description,'')))=any(array['K.CH','L.CH','MA','UEA','UEM','ÖT-1','ÖT-2','ÖT-3','ÖT-4','ÖT-5','ÖT-6']) and upper(trim(n.vehicle_registration))~'^[A-Z]{3}[0-9]{2}[A-Z0-9]$'
 and ((p_filters-array['date_from','date_to'])='{}'::jsonb or exists(select 1 from (select id,tenant_id,project_reference,project_name,cost_center,cost_center_name,business_group,registrations,valid_from,valid_to,source,created_at from private.hub_kpi_prepared_kpi_project_classification_periods where generation_id=report_generation) r where r.tenant_id=p_tenant_id and r.project_reference=n.project_reference and r.valid_from<=n.occurred_on and (r.valid_to is null or r.valid_to>=n.occurred_on) and (not(p_filters?'cost_center') or r.cost_center=any(string_to_array(p_filters->>'cost_center',','))) and (not(p_filters?'group') or r.business_group=any(string_to_array(p_filters->>'group',',')))))
 group by 1,2),
 worked as(select tt.hours+coalesce((select sum(n.hours) from next_daily n where not exists(select 1 from daily d where d.work_date=n.work_date and d.reg=n.vehicle)),0) hours from time_totals tt),
 revenue_days as materialized(select f.occurred_on work_date,array_agg(distinct e.external_id) vehicle_ids from facts f join (select id,tenant_id,connection_id,entity_type,external_id,source_updated_at,payload,payload_hash,first_seen_at,last_seen_at,created_at,updated_at from private.hub_kpi_prepared_hub_transpa_entities where generation_id=report_generation) e on e.tenant_id=p_tenant_id and e.entity_type='vehicle' and public.hub_normalize_vehicle_registration(e.payload->>'registrationNumber')=f.vehicle where f.kind='revenue' and f.amount<>0 group by f.occurred_on),
 eligible_time as materialized(select distinct original->>'time_report_id' report_id from facts where source='TransPA'),
 selected_time as materialized(select tenant_id,time_report_id,employee_id,work_date,work_hours,transpa_vehicle_ids from (select tenant_id,time_report_id,employee_id,person_object_id,started_at,work_date,work_minutes,work_hours,report_status,transpa_vehicle_ids,cost_distribution_codes,source_payload from private.hub_kpi_prepared_kpi_transpa_time_facts where generation_id=report_generation) where tenant_id=p_tenant_id and work_date between fy_from and fy_to and extract(month from work_date)::int=any(months)),
 driver_time as(select t.employee_id,t.work_hours,coalesce(t.transpa_vehicle_ids ?| rd.vehicle_ids,false) productive
 from selected_time t left join revenue_days rd on rd.work_date=t.work_date
 where t.tenant_id=p_tenant_id and t.work_date between fy_from and fy_to and extract(month from t.work_date)::int=any(months)
 and ((p_filters-array['date_from','date_to'])='{}'::jsonb or t.time_report_id::text in(select report_id from eligible_time))),
 drivers as(select employee_id driver,employee_id,sum(work_hours)::numeric total_hours,coalesce(sum(work_hours) filter(where productive),0)::numeric productive_hours,coalesce(sum(work_hours) filter(where not productive),0)::numeric unclassified_hours from driver_time group by employee_id),
 driver_totals as(select coalesce(sum(total_hours),0) hours,coalesce(sum(productive_hours),0) productive,coalesce(sum(unclassified_hours),0) unclassified from drivers),

 unit_versions as materialized(
 select u.id::text unit_key,v.valid_from,v.valid_to,coalesce((v.payload->>'enabled')::boolean,u.enabled) enabled,
 coalesce(nullif(v.payload->>'main_vehicle',''),nullif(v.payload->>'name',''),u.name) main_vehicle,v.payload->>'business_group_id' group_id
 from (select id,tenant_id,name,projects,registrations,employees,valid_from,valid_to,enabled,revision,created_at,updated_at,unit_type,origin from private.hub_kpi_prepared_kpi_units where generation_id=report_generation) u join (select id,tenant_id,unit_id,valid_from,valid_to,payload,created_by,created_at from private.hub_kpi_prepared_kpi_unit_periods where generation_id=report_generation) v on v.tenant_id=u.tenant_id and v.unit_id=u.id where u.tenant_id=p_tenant_id
 union all select u.id::text,u.valid_from,u.valid_to,u.enabled,u.name,null from (select id,tenant_id,name,projects,registrations,employees,valid_from,valid_to,enabled,revision,created_at,updated_at,unit_type,origin from private.hub_kpi_prepared_kpi_units where generation_id=report_generation) u where u.tenant_id=p_tenant_id and not exists(select 1 from (select id,tenant_id,unit_id,valid_from,valid_to,payload,created_by,created_at from private.hub_kpi_prepared_kpi_unit_periods where generation_id=report_generation) v where v.tenant_id=u.tenant_id and v.unit_id=u.id)
 ),
 selected_days as materialized(select dd::date dt,extract(month from dd)::int m,(extract(isodow from dd) between 1 and 5 and not public.hub_is_swedish_public_holiday(dd::date)) working_day from generate_series(fy_from,fy_to,interval '1 day') dd
 where extract(month from dd)::int=any(months) and (not(p_filters?'date_from') or dd::date>=(p_filters->>'date_from')::date) and (not(p_filters?'date_to') or dd::date<=(p_filters->>'date_to')::date)),
 unit_days as materialized(select u.key,d.dt,d.m,d.working_day,case when u.key like 'vehicle:%' then substr(u.key,9) else v.main_vehicle end main_vehicle,
 case when u.key like 'vehicle:%' then true else coalesce(v.enabled,false) end enabled,v.group_id
 from units u cross join selected_days d left join unit_versions v on v.unit_key=u.key and v.valid_from<=d.dt and (v.valid_to is null or v.valid_to>=d.dt)),
 unit_categories as(select unit_key,jsonb_object_agg(category,amount) categories from(
 select coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') unit_key,category,round(sum(amount),2) amount from facts where kind='cost' group by 1,2) c group by unit_key),
 unit_report_links as materialized(select distinct coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') unit_key,original->>'time_report_id' report_id from facts where source='TransPA' and original->>'time_report_id' is not null),
 report_units as(select report_id,count(*) unit_count from unit_report_links group by report_id),
 unit_revenue_days as materialized(select distinct coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') unit_key,occurred_on work_date from facts where kind='revenue' and amount<>0),
 unit_driver_time as(select l.unit_key,count(*) reports,bool_and(r.unit_count=1) unambiguous,sum(t.work_hours)::numeric worked_hours,
 coalesce(sum(t.work_hours) filter(where rd.unit_key is not null),0)::numeric productive_hours
 from unit_report_links l join report_units r using(report_id) join selected_time t on t.time_report_id=l.report_id left join unit_revenue_days rd on rd.unit_key=l.unit_key and rd.work_date=t.work_date group by l.unit_key),
 unit_vehicle_links as materialized(select distinct coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned') unit_key,f.occurred_on dt,f.vehicle
 from facts f where f.source='TransPA' and f.vehicle is not null),
 unit_occupied as(select l.unit_key,sum(d.reported_vehicle_hours)::numeric occupied_hours from unit_vehicle_links l join daily d on d.reg=l.vehicle and d.work_date=l.dt
 join unit_days ud on ud.key=l.unit_key and ud.dt=l.dt and ud.main_vehicle=l.vehicle and ud.enabled group by l.unit_key),
 unit_capacity as(select ud.key,sum(case when ud.working_day
 and ud.enabled and ud.dt>=fs.first_seen
 and (not(p_filters?'cost_center') or exists(select 1 from (select id,tenant_id,project_reference,project_name,cost_center,cost_center_name,business_group,registrations,valid_from,valid_to,source,created_at from private.hub_kpi_prepared_kpi_project_classification_periods where generation_id=report_generation) r where r.tenant_id=p_tenant_id and ud.main_vehicle=any(r.registrations) and r.valid_from<=ud.dt and (r.valid_to is null or r.valid_to>=ud.dt) and r.cost_center=any(string_to_array(p_filters->>'cost_center',','))))
 and (not(p_filters?'group') or exists(select 1 from (select id,tenant_id,name,code,sort_order,enabled,created_at,updated_at from private.hub_kpi_prepared_kpi_business_groups where generation_id=report_generation) g where g.tenant_id=p_tenant_id and g.id::text=ud.group_id and g.name=any(string_to_array(p_filters->>'group',',')))
 or (ud.group_id is null and exists(select 1 from (select id,tenant_id,project_reference,project_name,cost_center,cost_center_name,business_group,registrations,valid_from,valid_to,source,created_at from private.hub_kpi_prepared_kpi_project_classification_periods where generation_id=report_generation) r where r.tenant_id=p_tenant_id and ud.main_vehicle=any(r.registrations) and r.valid_from<=ud.dt and (r.valid_to is null or r.valid_to>=ud.dt) and r.business_group=any(string_to_array(p_filters->>'group',',')))))
 then coalesce((select s.vehicle_capacity_hours_per_day::numeric from (select tenant_id,currency,timezone,financial_year_start_month,financial_year_start_day,vehicle_capacity_hours_per_day,updated_by,created_at,updated_at from private.hub_kpi_prepared_kpi_settings where generation_id=report_generation) s where s.tenant_id=p_tenant_id),8) else 0 end)::numeric available_hours
 from unit_days ud join (select d.reg,min(f.first_seen) first_seen from daily d join first_seen f using(vehicle_id) group by d.reg) fs on fs.reg=ud.main_vehicle group by ud.key),
 unit_distance_spans as materialized(select key,m,min(dt) df,max(dt) dt,case when count(distinct main_vehicle)=1 and bool_and(enabled) then max(main_vehicle) end registration from unit_days group by key,m),
 distance_manual as(select s.key,s.m,case when min(p.period_from)=s.df and max(p.period_to)=s.dt and sum(p.period_to-p.period_from+1)=s.dt-s.df+1 then sum(p.distance_km) end km
 from unit_distance_spans s left join (select id,tenant_id,vehicle_object_id,registration,period_from,period_to,distance_km,ingress_id,source_row,fingerprint,created_by,created_at from private.hub_kpi_prepared_kpi_vehicle_distance_periods where generation_id=report_generation) p on p.tenant_id=p_tenant_id and p.registration=s.registration and p.period_from>=s.df and p.period_to<=s.dt group by s.key,s.m,s.df,s.dt),
 distance_assets as(select public.hub_normalize_vehicle_registration(data->>'registration_number') registration,(array_agg(id))[1] id from (select id,tenant_id,object_type,status,data,source_of_truth,version,created_at,updated_at from private.hub_kpi_prepared_hub_objects where generation_id=report_generation) where tenant_id=p_tenant_id and object_type='Vehicle' group by 1 having count(*)=1),
 distance_estimates as materialized(select s.key,s.m,coalesce(c.estimate,private.hub_kpi_prepared_distance_v1(p_tenant_id,a.id,s.df,s.dt)) estimate from unit_distance_spans s join distance_assets a on a.registration=s.registration left join private.hub_kpi_prepared_month_distance c on c.generation_id=report_generation and c.tenant_id=p_tenant_id and c.vehicle_id=a.id and c.date_from=s.df and c.date_to=s.dt),
 distance_meters as(select key,m,(estimate->>'distance_km')::numeric km,estimate from distance_estimates),
 unit_distance as(select s.key,case when bool_and(coalesce(a.km,b.km) is not null) then sum(coalesce(a.km,b.km))/10 end distance_mil,
 count(*) filter(where coalesce(a.km,b.km) is null) missing_months,
 bool_or(a.km is null and b.estimate->>'basis'='interpolated') estimated,
 jsonb_agg(jsonb_build_object('month',s.m,'from',s.df,'to',s.dt,'distance_mil',coalesce(a.km,b.km)/10,'basis',case when a.km is not null then 'period_import' else coalesce(b.estimate->>'basis','missing') end,'measurement_basis',case when a.km is null then b.estimate end) order by s.df) distance_monthly
 from unit_distance_spans s left join distance_manual a using(key,m) left join distance_meters b using(key,m) group by s.key),
 unit_fuel_quantity as(select coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') key,case when bool_and(source='Piusi' or amount=0) then sum((original#>>'{_humla_fuel,quantity_liters}')::numeric) end liters from facts where kind='cost' and category='fuel' group by 1),
 unit_performance as(select u.key,
 jsonb_build_object('cost_categories',jsonb_build_object('personnel',0,'fuel',0,'service_repair',0,'depreciation',0,'fixed',0,'other',0,'material',0,'tipp_deponi',0,'hired',0)||coalesce(c.categories,'{}'::jsonb),
 'margin_pct',round(u.result/nullif(u.revenue,0)*100,2),
 'worked_hours',case when t.unambiguous then round(t.worked_hours,2) end,
 'productive_hours',case when t.unambiguous then round(t.productive_hours,2) end,
 'billing_percent',case when t.unambiguous then round(t.productive_hours/nullif(t.worked_hours,0)*100,1) end,
 'billing_basis','intäktskopplad TransPA-tid / arbetad TransPA-tid; inte verifierade fakturerade timmar',
 'occupied_hours',round(o.occupied_hours,2),'available_hours',round(a.available_hours,2),
 'utilization',round(o.occupied_hours/nullif(a.available_hours,0)*100,1),
 'revenue_per_hour',case when t.unambiguous then round(u.revenue/nullif(t.worked_hours,0),2) end,
 'cost_per_hour',case when t.unambiguous then round(u.cost/nullif(t.worked_hours,0),2) end,
 'distance_mil',round(d.distance_mil,2),'cost_per_mil',round(u.cost/nullif(d.distance_mil,0),2),'revenue_per_mil',round(u.revenue/nullif(d.distance_mil,0),2),
 'fuel_cost_per_mil',round(coalesce((c.categories->>'fuel')::numeric,0)/nullif(d.distance_mil,0),2),'fuel_liters_per_mil',round(q.liters/nullif(d.distance_mil,0),2),
 'distance_basis',case when d.distance_mil is null then 'missing_complete_period' when d.estimated then 'main_vehicle_interpolated_period' else 'main_vehicle_exact_period' end,
 'distance_monthly',d.distance_monthly,'missing_distance_months',d.missing_months) performance
 from units u left join unit_fuel_quantity q on q.key=u.key left join unit_categories c on c.unit_key=u.key left join unit_driver_time t on t.unit_key=u.key left join unit_occupied o on o.unit_key=u.key left join unit_capacity a on a.key=u.key left join unit_distance d on d.key=u.key),
 vehicle_categories as materialized(select vehicle,jsonb_object_agg(category,amount)categories from(
 select vehicle,category,sum(amount)amount from facts where kind='cost'group by vehicle,category)c group by vehicle),
 vehicles as(select coalesce(f.vehicle,'Ej fördelat') vehicle,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result,round(coalesce(sum(amount) filter(where category='fuel' and kind='cost'),0),2) fuel_cost,round(coalesce(sum(amount) filter(where source='TransPA'),0),2) personnel_cost from facts f group by f.vehicle)
 select jsonb_build_object(
 'invoice_lead_time',private.hub_kpi_invoice_lead_time_v1(p_tenant_id,p_fiscal_year,months,p_filters,-1),'hub_contract_version','fiscal-months-v1','period',jsonb_build_object('fiscal_year',p_fiscal_year,'selected_months',months,'from',fy_from,'to',fy_to),'filters',p_filters,
 'coverage',(select jsonb_build_object('revenue_months',coalesce(jsonb_agg(m)filter(where revenue_rows>0),'[]'),'cost_months',coalesce(jsonb_agg(m)filter(where next_rows>0),'[]'))from(select m,count(f.fact_id)filter(where f.source='Workify') revenue_rows,count(f.fact_id)filter(where f.source='NEXT')next_rows from unnest(months)m left join selected_facts f on extract(month from f.occurred_on)::int=m group by m)x),
 'metrics',jsonb_build_object('revenue',round(t.revenue,2),'total_cost',round(t.cost,2),'result',round(t.revenue-t.cost,2),'margin_pct',round((t.revenue-t.cost)/nullif(t.revenue,0)*100,2),'revenue_per_vehicle',case when exists(select 1 from facts where jsonb_typeof(original->'_humla_material_separation')='object') then round((select coalesce(sum(amount),0) from facts where kind='revenue' and vehicle not in('LASTBIL','INHYRDLASTBIL','Ej fördelat',''))/nullif(t.vehicles,0),2) else round((t.revenue-t.hired)/nullif(t.vehicles,0),2) end,'diesel_share',round(coalesce((select amount from cats where category='fuel'),0)/nullif(t.revenue,0)*100,2),'vehicle_utilization',round(tt.hours/nullif(tt.available,0)*100,1)),
 'components',(select jsonb_build_object('piusi_fuel_cost',round(coalesce(sum(amount) filter(where source='Piusi'),0),2),'next_total_cost',round(coalesce(sum(amount) filter(where source='NEXT'),0),2),'transpa_personnel_cost',round(coalesce(sum(amount) filter(where source='TransPA'),0),2),'depreciation_cost',round(coalesce(sum(amount) filter(where kind='cost' and category='depreciation'),0),2)) from facts),
 'monthly',(select jsonb_agg(jsonb_build_object('month',m,'period_start',dt,'period_end',(dt+interval '1 month'-interval '1 day')::date,'revenue',round(revenue,2),'cost',round(cost,2),'result',round(revenue-cost,2),'rows',rows) order by dt) from monthly),
 'business_groups',coalesce((select jsonb_agg(to_jsonb(g) order by label) from groups g),'[]'),
 'group_options',coalesce((select jsonb_agg(business_group order by business_group) from (
 select distinct f.business_group from private.hub_kpi_report_display_facts_v1 f
 where f.generation_id=report_generation and f.tenant_id=p_tenant_id and f.fiscal_year=p_fiscal_year and f.occurred_on between selected_from and selected_to
 and extract(month from f.occurred_on)::int=any(months)
 and (not(p_filters?'cost_center') or f.cost_center=any(string_to_array(p_filters->>'cost_center',',')))
 and (not(p_filters?'date_from') or f.occurred_on>=(p_filters->>'date_from')::date)
 and (not(p_filters?'date_to') or f.occurred_on<=(p_filters->>'date_to')::date)
 and nullif(trim(f.business_group),'') is not null
 ) available_groups),'[]'::jsonb),
 'economic_units',coalesce((select jsonb_agg(to_jsonb(u)||p.performance||jsonb_build_object('children',coalesce((select jsonb_agg(to_jsonb(c) order by label)from unit_children c where c.unit_key=u.key),'[]')) order by label) from units u join unit_performance p using(key)),'[]'),
 'cost_categories',jsonb_build_object('personnel',0,'fuel',0,'service_repair',0,'depreciation',0,'fixed',0,'other',0,'material',0,'tipp_deponi',0,'hired',0)||coalesce((select jsonb_object_agg(category,amount) from cats),'{}'),
 'vehicles',coalesce((select jsonb_agg(to_jsonb(v)||jsonb_build_object('cost_categories',coalesce(vc.categories,'{}'::jsonb),'occupied_hours',vt.hours,'available_hours',vt.available_hours,'utilization',round(vt.hours/nullif(vt.available_hours,0)*100,1),'revenue_per_hour',round(v.revenue/nullif(vt.hours,0),2)) order by v.vehicle) from vehicles v left join vehicle_time vt using(vehicle)left join vehicle_categories vc using(vehicle)),'[]'),
 'drivers',coalesce((select jsonb_agg(to_jsonb(d)) from drivers d),'[]'),'unmapped_accounts','[]'::jsonb,
 'unit_assignment_summary',(select jsonb_build_object('rows',count(*),'revenue',round(coalesce(sum(amount)filter(where kind='revenue'),0),2),'cost',round(coalesce(sum(amount)filter(where kind='cost'),0),2)) from facts where unit_id is null),
 'unclassified_summary',(select jsonb_build_object('revenue',round(coalesce(sum(amount) filter(where kind='revenue'),0),2),'cost',round(coalesce(sum(amount) filter(where kind='cost'),0),2),'rows',count(*)) from selected_facts where cost_center='unclassified'),
 'material_separation',(select jsonb_build_object('active',count(*)>0,'review_rows',count(*)filter(where original#>>'{_humla_material_separation,status}'='needs_review'),'split_rows',count(*)filter(where original#>>'{_humla_material_separation,component}'='transport')) from facts where jsonb_typeof(original->'_humla_material_separation')='object'),'quality',(select jsonb_build_object('total_rows',count(*),'valid_rows',count(*),'rows_without_vehicle',count(*) filter(where vehicle is null),'rows_without_employee',0,'rows_without_account_mapping',0,'basis','Hub authoritative financial facts') from facts),
 'transpa_vehicle_time',jsonb_build_object('reported_hours',round(tt.hours,2),'available_hours',round(tt.available,2),'vehicle_count',tt.vehicles,'utilization',round(tt.hours/nullif(tt.available,0)*100,1),'vehicles',coalesce((select jsonb_agg(to_jsonb(v)||jsonb_build_object('occupied_hours',hours,'utilization',round(hours/nullif(available_hours,0)*100,1))) from vehicle_time v),'[]')),
 'efficiency',jsonb_build_object('worked_hours',round(w.hours,2),'revenue',round(t.revenue,2),'own_revenue',round(t.revenue-t.hired,2),'hired_revenue',round(t.hired,2),'revenue_per_worked_hour',round((t.revenue-t.hired)/nullif(w.hours,0),2)),
 'hired_capacity',jsonb_build_object('total_revenue',round(t.revenue,2),'hired_revenue',round(t.hired,2),'hired_share_percent',round(t.hired/nullif(t.revenue,0)*100,2)),
 'driver_productivity',jsonb_build_object('total_hours',round(d.hours,2),'productive_hours',round(d.productive,2),'unclassified_hours',round(d.unclassified,2),'productive_percent',round(d.productive/nullif(d.hours,0)*100,1),'drivers',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('productive_percent',round(productive_hours/nullif(total_hours,0)*100,1))) from drivers x),'[]')),
 'cost_efficiency',coalesce((select jsonb_object_agg(category||'_cost_per_hour',round(amount/nullif(w.hours,0),2)) from cats),'{}')||jsonb_build_object('worked_hours',round(w.hours,2),'total_cost_per_hour',round(t.cost/nullif(w.hours,0),2),'result_per_hour',round((t.revenue-t.cost)/nullif(w.hours,0),2),'direct_cost_per_hour',null,'common_cost_per_hour',null,'overhead_cost_per_hour',null,'contribution_per_hour',null),
 'personnel_basis','TransPA-tid × Hub-schablon; inte verifierad löneexport',
 'reconciliation',jsonb_build_object('matches',t.revenue=(select sum(revenue) from monthly) and t.cost=(select sum(cost) from monthly),'vehicle_rows_match',abs(round(t.revenue,2)-(select coalesce(sum(revenue),0) from vehicles))<=0.01*(select count(*) from vehicles) and abs(round(t.cost,2)-(select coalesce(sum(cost),0) from vehicles))<=0.01*(select count(*) from vehicles),'source','Hub authoritative classified facts, exact selected months')
 ) into output from totals t cross join time_totals tt cross join worked w cross join driver_totals d;

 output:=private.hub_kpi_worked_time_projection_v1(output,
  private.hub_kpi_next_time_period_v1(p_tenant_id,p_fiscal_year,months,p_filters),
  (select count(*)*coalesce((select vehicle_capacity_hours_per_day from private.hub_kpi_prepared_kpi_settings where tenant_id=p_tenant_id and generation_id=report_generation),8)
   from generate_series(fy_from,fy_to,interval '1 day')d where extract(month from d)::int=any(months)
    and extract(isodow from d)between 1 and 5 and not public.hub_is_swedish_public_holiday(d::date)));
 return output;
end $function$;
-- Full-year cold calculations need headroom; the completed result is scope-cached.
alter function public.hub_kpi_overview_months_v1(uuid,integer,integer[],text,jsonb)set statement_timeout='45s';
alter function private.hub_kpi_prepared_overview_v1(uuid,integer,integer[],text,jsonb)set statement_timeout='45s';
notify pgrst,'reload schema';
