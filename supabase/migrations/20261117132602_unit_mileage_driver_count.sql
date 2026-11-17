-- Keep the approved meter engine. For an open month, move the end only
-- to a midnight supported by the same quality-checked series.
create function private.hub_kpi_unit_meter_span_v1(
 p_tenant uuid,p_generation uuid,p_vehicle uuid,p_from date,p_to date,p_as_of date
) returns jsonb language plpgsql stable set search_path='' as $$
declare series jsonb; evidence jsonb; covered_to date;
begin
 series:=private.hub_meter_series_v1(p_tenant,p_generation,p_vehicle,p_from,p_to);
 evidence:=private.hub_meter_span_engine_v1(series,p_from,p_to);
 if evidence->>'basis'='missing_bracketing_readings'
    and date_trunc('month',p_to)=date_trunc('month',p_as_of) then
  select least(p_to,p_as_of-1,max((v.at at time zone 'Europe/Stockholm')::date)-1)
  into covered_to from jsonb_to_recordset(series->'points') v(at timestamptz)
  having count(*)>0;
  if covered_to between p_from and p_to-1 then
   evidence:=private.hub_meter_span_engine_v1(series,p_from,covered_to);
   if evidence->>'distance_km' is not null then
    return evidence||jsonb_build_object('covered_to',covered_to);
   end if;
  end if;
 end if;
 return evidence;
end $$;
revoke all on function private.hub_kpi_unit_meter_span_v1(uuid,uuid,uuid,date,date,date) from public,anon,authenticated;

-- A null report-ID list means tenant-wide TransPA time. An empty array means
-- a scoped selection in which no published time report matched.
create function private.hub_kpi_driver_count_v1(
 p_tenant uuid,p_generation uuid,p_from date,p_to date,p_months integer[],
 p_report_ids text[],p_invoice_facts jsonb
) returns jsonb language sql stable set search_path='' as $$
 with people as materialized (
  select o.id,o.data->>'display_name' name,
   regexp_replace(lower(btrim(o.data->>'display_name')),'[[:space:]]+',' ','g') normalized_name
  from public.hub_objects o where o.tenant_id=p_tenant and o.object_type='Person'
 ), native as (
  select distinct coalesce(coalesce(t.person_object_id,k.object_id)::text,'transpa:'||t.employee_id) person,
   coalesce(nullif(btrim(o.name),''),nullif(btrim(e.display_name),''),'TransPA '||t.employee_id) name
  from private.hub_kpi_prepared_kpi_transpa_time_facts t
  left join public.hub_identity_keys k on k.tenant_id=p_tenant and k.identity_type='transpa_employee_id'
   and k.identity_value=t.employee_id and k.object_type='Person' and k.confidence=1
  left join people o on o.id=coalesce(t.person_object_id,k.object_id)
  left join lateral (
   select min(display_name) display_name, bool_or(profession_group='driver') is_driver
   from public.hub_transpa_persons p where p.tenant_id=p_tenant and p.transpa_employee_id=t.employee_id
  ) e on true
  where t.tenant_id=p_tenant and t.generation_id=p_generation and t.work_hours>0
   and t.work_date between p_from and p_to and nullif(btrim(t.employee_id),'') is not null
   and (p_months is null or extract(month from t.work_date)::int=any(p_months))
   and (p_report_ids is null or t.time_report_id=any(p_report_ids))
   and e.is_driver is distinct from false
 ), invoices as (
  select f.vehicle,b.original->>'Leverantör' supplier,f.amount
  from jsonb_to_recordset(p_invoice_facts) f(fact_id text,vehicle text,amount numeric)
  join private.hub_kpi_report_facts_v1 b on b.tenant_id=p_tenant and b.generation_id=p_generation and b.fact_id=f.fact_id
  where b.account='4411'
 ), configured as (
  select r.target_vehicle_registration vehicle,m.id::text person,m.name,
    regexp_replace(lower(btrim(r.driver_name)),'[[:space:]]+',' ','g') rule_name
  from public.hub_workify_driver_vehicle_rules r
  join lateral (select (array_agg(id))[1] id,min(name) name from people
   where normalized_name=regexp_replace(lower(btrim(r.driver_name)),'[[:space:]]+',' ','g') having count(*)=1) m on true
  where r.tenant_id=p_tenant and r.rule_source='user_confirmed'
 ), exceptions as (
  select r.person,r.name,array_agg(distinct r.vehicle order by r.vehicle) vehicles
  from configured r join invoices i on public.hub_normalize_vehicle_registration(i.vehicle)=r.vehicle
   and regexp_replace(lower(btrim(i.supplier)),'[[:space:]]+',' ','g')
    in (r.rule_name,r.rule_name||' enskild firma',r.rule_name||' ab',r.rule_name||' aktiebolag')
  group by r.person,r.name having sum(i.amount)>0
 ), entries as (
  select coalesce(n.person,e.person) person,coalesce(n.name,e.name) name,n.person is not null transpa,e.vehicles
  from (select person,min(name) name from native group by person) n full join exceptions e using(person)
 )
 select jsonb_build_object('count',count(*),'transpa_count',count(*) filter(where transpa),
  'exception_count',count(*) filter(where not transpa),'people',coalesce(jsonb_agg(jsonb_build_object(
   'name',name,'source',case when transpa then 'TransPA' else 'Fordonsundantag' end,'vehicles',coalesce(vehicles,array[]::text[])
  ) order by name,person),'[]'::jsonb))
 from entries;
$$;
revoke all on function private.hub_kpi_driver_count_v1(uuid,uuid,date,date,integer[],text[],jsonb) from public,anon,authenticated;


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
 unit_children as materialized(select coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') unit_key,case when original?'_humla_monthly_overhead' then 'overhead:'||category||':'||(original#>>'{_humla_monthly_overhead,rule_id}') when original#>>'{_humla_distribution,status}'='allocated' then 'shared:'||coalesce(project,'utan projekt') else coalesce(vehicle,'project:'||project,'unassigned') end key,max(case when original?'_humla_monthly_overhead' then original#>>'{_humla_monthly_overhead,rule_name}' when original#>>'{_humla_distribution,status}'='allocated' then 'Gemensam kostnad · '||coalesce(project,'utan projekt') else coalesce(vehicle,project,'Ej fördelat') end) label,max(case when original#>>'{_humla_distribution,status}'<>'allocated' or original#>>'{_humla_distribution,status}' is null then vehicle end) vehicle,max(project) project,count(*) rows,round(coalesce(sum(amount)filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount)filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by 1,2),
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
 unit_distance_spans as materialized(select key,m,min(dt) df,max(dt) dt,
  case when count(distinct public.hub_normalize_vehicle_registration(main_vehicle))=1
   and bool_and(enabled is true and main_vehicle is not null) and count(*)=count(distinct dt)
   then max(public.hub_normalize_vehicle_registration(main_vehicle)) end registration
  from unit_days group by key,m),
 distance_spans as materialized(
  select s.*,case when not exists (select 1 from unit_distance_spans x
   where x.key<>s.key and x.registration=s.registration and x.df<=s.dt and x.dt>=s.df)
   then s.registration end unique_registration
  from unit_distance_spans s
 ),
 distance_manual as(
  select s.key,s.m,case when range_agg(daterange(p.period_from,p.period_to,'[]'))=datemultirange(daterange(s.df,s.dt,'[]'))
    and sum(p.period_to-p.period_from+1)=s.dt-s.df+1 then sum(p.distance_km) end km
  from distance_spans s left join private.hub_kpi_prepared_kpi_vehicle_distance_periods p
   on p.generation_id=report_generation and p.tenant_id=p_tenant_id and p.registration=s.unique_registration and p.period_from>=s.df and p.period_to<=s.dt
  group by s.key,s.m,s.df,s.dt
 ),
 distance_assets as(
  select public.hub_normalize_vehicle_registration(data->>'registration_number') registration,(array_agg(id))[1] id
  from private.hub_kpi_prepared_hub_objects where generation_id=report_generation and tenant_id=p_tenant_id and object_type='Vehicle'
  group by 1 having count(*)=1
 ),
 distance_estimates as materialized(
  select s.key,s.m,case when c.estimate->>'distance_km' is not null then c.estimate
   else private.hub_kpi_unit_meter_span_v1(p_tenant_id,report_generation,a.id,s.df,s.dt,(now() at time zone 'Europe/Stockholm')::date) end estimate
  from distance_spans s join distance_assets a on a.registration=s.unique_registration
  left join private.hub_kpi_prepared_month_distance c on c.generation_id=report_generation and c.tenant_id=p_tenant_id
   and c.vehicle_id=a.id and c.date_from=s.df and c.date_to=s.dt
  left join distance_manual ma on ma.key=s.key and ma.m=s.m
  where ma.km is null
 ),
 distance_periods as materialized(
  select s.key,s.m,s.df,s.dt,coalesce(a.km,(b.estimate->>'distance_km')::numeric) km,
   case when a.km is not null then 'period_import' else coalesce(b.estimate->>'basis','missing') end basis,
   case when a.km is null then b.estimate end estimate,
   coalesce((b.estimate->>'covered_to')::date,s.dt) covered_to
  from distance_spans s left join distance_manual a using(key,m) left join distance_estimates b using(key,m)
 ),
 distance_amounts as (
  select s.key,sum(f.amount) filter(where f.kind='cost') matched_cost,
   sum(f.amount) filter(where f.kind='revenue') matched_revenue,
   sum(f.amount) filter(where f.kind='cost' and f.category='fuel') matched_fuel,
   case when bool_and(f.source='Piusi' or f.amount=0) filter(where f.kind='cost' and f.category='fuel')
    then sum((f.original#>>'{_humla_fuel,quantity_liters}')::numeric) filter(where f.kind='cost' and f.category='fuel') end matched_liters
  from distance_periods s left join facts f on coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=s.key
   and f.occurred_on between s.df and s.covered_to
  where s.km is not null group by s.key
 ),
 unit_distance as(
  select s.key,sum(s.km)/10 distance_mil,
   count(*) filter(where s.km is null or s.covered_to<s.dt) missing_months,
   bool_or(s.basis='interpolated') estimated,
   jsonb_agg(jsonb_build_object('month',s.m,'from',s.df,'to',s.dt,'covered_to',case when s.km is not null then s.covered_to end,
    'distance_mil',s.km/10,'basis',s.basis,'measurement_basis',s.estimate) order by s.df) distance_monthly
  from distance_periods s group by s.key
 ),
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
 'distance_mil',round(d.distance_mil,2),'cost_per_mil',round(coalesce(da.matched_cost,0)/nullif(d.distance_mil,0),2),'revenue_per_mil',round(coalesce(da.matched_revenue,0)/nullif(d.distance_mil,0),2),
 'fuel_cost_per_mil',round(coalesce(da.matched_fuel,0)/nullif(d.distance_mil,0),2),'fuel_liters_per_mil',round(da.matched_liters/nullif(d.distance_mil,0),2),
 'distance_basis',case when d.distance_mil is null then 'missing_complete_period' when d.estimated then 'main_vehicle_interpolated_period' else 'main_vehicle_exact_period' end,
 'distance_monthly',d.distance_monthly,'missing_distance_months',d.missing_months) performance
 from units u left join unit_categories c on c.unit_key=u.key left join unit_driver_time t on t.unit_key=u.key left join unit_occupied o on o.unit_key=u.key left join unit_capacity a on a.key=u.key left join unit_distance d on d.key=u.key left join distance_amounts da on da.key=u.key),
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
 'driver_count',private.hub_kpi_driver_count_v1(p_tenant_id,report_generation,fy_from,fy_to,months,
  case when (p_filters-array['date_from','date_to'])<>'{}'::jsonb
   then array(select report_id from eligible_time where report_id is not null) end,
  (select coalesce(jsonb_agg(jsonb_build_object('fact_id',fact_id,'vehicle',vehicle,'amount',amount)),'[]')
   from facts where source='NEXT' and kind='cost' and category='personnel' and vehicle is not null)),
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

CREATE OR REPLACE FUNCTION public.hub_transport_leader_scorecard_v4(p_tenant uuid, p_from date, p_to date, p_user uuid DEFAULT NULL::uuid, p_unit uuid DEFAULT NULL::uuid, p_page integer DEFAULT 0, p_months integer[] DEFAULT NULL::integer[], p_group text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare output jsonb; time_basis jsonb; hours numeric; time_to date; time_revenue numeric; time_cost numeric; covered int; ola_view boolean;
begin
 if p_months is not null and (cardinality(p_months)=0 or not p_months <@ array[1,2,3,4,5,6,7,8,9,10,11,12]) then raise exception 'Invalid months';end if;
 if p_page is null or p_page<0 or p_page>10000 then raise exception 'Invalid page';end if;
 select p_group is null and (p_user='00000000-0000-0000-0000-000000000030'::uuid or exists(
  select 1 from public.hub_tenant_members m
  where m.tenant_id=p_tenant and m.user_id=p_user and m.status='active'
    and trim(m.display_name) ~* '^ola([[:space:]]|$)'
 )) into ola_view;
 with scope_facts as materialized(select f.*,
  case
   when ola_view is not true then f.business_group
   when p_user is distinct from '00000000-0000-0000-0000-000000000030'::uuid
    and f.unit_name in ('Grusmaterial - Lager','Grusmaterial Försäljning') then 'Grusmaterial Försäljning'
   when f.unit_name in ('WCF22U','LZP91Z','HGL39H') then 'Asfaltskörning'
   when f.unit_name='DUN012' then 'Fasta uppdrag'
   when f.unit_name='Inhyrda bilar' or f.business_group='Inhyrda lastbilar' then 'Bygg & Anläggning'
   else f.business_group
  end as view_group,
  case when ola_view and f.unit_name='Grusmaterial - Lager'
   then 'Grusmaterial Försäljning' else f.unit_name end as view_unit_name
 from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user) f where (p_months is null or extract(month from f.occurred_on)::integer=any(p_months))),
 facts as materialized(select f.*,case when f.category='material' then 'material' when f.category in ('tipp','tipp_deponi') then 'tipp' when f.category='transport' then 'transport' else 'other' end section
 from scope_facts f where (p_unit is null or f.unit_id=p_unit) and (p_group is null or coalesce(nullif(f.business_group,''),'Ej klassificerat')=p_group) and (p_months is null or extract(month from f.occurred_on)::integer=any(p_months))),
 enriched as materialized(select f.*,coalesce(t.margin_percent,g.margin_percent,20::numeric) margin_percent from facts f left join private.hub_transport_unit_targets_v2 t on t.tenant_id=f.tenant_id and t.unit_id=f.unit_id and t.valid_from<=f.occurred_on and(t.valid_to is null or t.valid_to>=f.occurred_on) left join private.hub_transport_group_targets_v1 g on g.tenant_id=f.tenant_id and g.business_group=f.business_group),
 totals as(select unit_id,min(view_unit_name) unit_name,
 coalesce(nullif(view_group,''),'Ej klassificerat') business_group,
 grouping(unit_id,view_group) level,count(*) rows,
 coalesce(sum(amount)filter(where kind='revenue'),0) revenue,coalesce(sum(amount)filter(where kind='cost'),0) cost,
 count(*)filter(where kind='revenue' and amount<>0 and margin_percent is null) missing_targets,
 sum(amount*margin_percent/100)filter(where kind='revenue') target_result
 from enriched group by grouping sets ((unit_id),(view_group),())),
 metrics as(select *,revenue-cost result,case when revenue>0 then (revenue-cost)/revenue*100 end margin_percent,
 case when missing_targets=0 and revenue>0 and target_result is not null then target_result/revenue*100 end target_margin_percent,
 case when missing_targets=0 and target_result is not null then revenue-cost-target_result end deviation_amount,
 case when missing_targets=0 and revenue>0 and target_result is not null then ((revenue-cost)-target_result)/revenue*100 end deviation_pp from totals),
 unit_cost_rows as materialized(select unit_id,category,sum(amount) amount,count(*) rows from facts where kind='cost' group by unit_id,category),
 unit_cost_breakdowns as materialized(select unit_id,jsonb_agg(jsonb_build_object('category',category,'amount',amount,'rows',rows) order by category) cost_breakdown from unit_cost_rows group by unit_id),
 units as(select * from metrics where level=1),
 breakdown as(select kind,category,sum(amount) amount,count(*) rows from facts group by kind,category),
 sections as(select section,coalesce(sum(amount)filter(where kind='revenue'),0) revenue,coalesce(sum(amount)filter(where kind='cost'),0) cost,count(*) rows from facts group by section),
 analysis_finance as materialized(
 select unit_id,min(view_unit_name) unit_name,coalesce(nullif(view_group,''),'Ej klassificerat') business_group,
 coalesce(sum(amount)filter(where kind='revenue'),0) revenue,
 coalesce(sum(amount)filter(where kind='cost' and category='personnel'),0) personnel,
 coalesce(sum(amount)filter(where kind='cost' and category='service_repair'),0) service_repair,
 coalesce(sum(amount)filter(where kind='cost' and category='fuel'),0) fuel,
 count(*)filter(where kind='cost' and category='personnel' and source<>'TransPA') other_personnel_rows
 from scope_facts where unit_id is not null group by unit_id,coalesce(nullif(view_group,''),'Ej klassificerat')
 ),
 time_ids as materialized(select distinct original->>'time_report_id' time_report_id from scope_facts
 where source='TransPA' and category='personnel' and original->>'time_report_id' is not null),
 -- Resolve time through the already published canonical unit link. Never divide a
 -- person's full report among vehicles by cost or by a guessed registration.
 time_links as materialized(
 select f.original->>'time_report_id' time_report_id,(array_agg(distinct f.unit_id))[1] unit_id,
 min(coalesce(nullif(f.business_group,''),'Ej klassificerat')) business_group,
 count(distinct f.unit_id)=1 and bool_and(f.unit_id is not null)
 and count(distinct coalesce(nullif(f.business_group,''),'Ej klassificerat'))=1 unambiguous
 from private.hub_kpi_prepared_display_facts f
 where f.tenant_id=p_tenant and f.generation_id=(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant)
 and f.source='TransPA' and f.category='personnel' and f.original->>'time_report_id' is not null group by f.original->>'time_report_id'
 ),
 analysis_time as(
 select a.unit_id,a.business_group,sum(t.work_hours) hours,
 count(*)filter(where not l.unambiguous or t.work_hours is null or t.work_hours<0) uncertain_reports
 from analysis_finance a join (select distinct unit_id,coalesce(nullif(view_group,''),'Ej klassificerat') business_group,original->>'time_report_id' time_report_id
 from scope_facts where source='TransPA' and category='personnel') s using(unit_id,business_group)
 join time_links l using(time_report_id)
 left join private.hub_kpi_prepared_kpi_transpa_time_facts t on t.tenant_id=p_tenant
 and t.generation_id=(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant)
 and t.time_report_id=s.time_report_id and t.work_date between p_from and p_to
 group by a.unit_id,a.business_group
 ),
 analysis_inputs as(select a.*,case when a.other_personnel_rows=0 and t.uncertain_reports=0 and t.hours>0 then t.hours end worked_hours
 from analysis_finance a left join analysis_time t using(unit_id,business_group)),
 details as(select fact_id,occurred_on,kind,amount,category,unit_id,view_unit_name as unit_name,project,vehicle,source,cost_center,
 original#>>'{_humla_invoice,order_number}' order_number,original#>>'{_humla_invoice,customer_name}' customer,
 original->'_humla_cost_rule' allocation_rule,original from facts order by occurred_on desc,fact_id limit 100 offset p_page*100)
 select jsonb_build_object('from',p_from,'to',p_to,
 'scope',case when p_user is null and exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role='owner') then 'transport' else 'assigned' end,
 'summary',(select to_jsonb(m)||jsonb_build_object('revenue',case when rows>0 then revenue end,'cost',case when rows>0 then cost end,'result',case when rows>0 then result end,'unassigned_rows',(select count(*) from facts where unit_id is null)) from metrics m where level=3),
 'groups',(select coalesce(jsonb_agg(to_jsonb(m) order by business_group),'[]') from metrics m where level=2),
 'breakdown',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('share_of_revenue',case when m.revenue>0 then b.amount/m.revenue*100 end) order by b.kind,b.category),'[]') from breakdown b cross join metrics m where m.level=3),
 'units',(select coalesce(jsonb_agg(to_jsonb(u)||jsonb_build_object('cost_breakdown',coalesce((select c.cost_breakdown from unit_cost_breakdowns c where c.unit_id is not distinct from u.unit_id),'[]'::jsonb)) order by unit_name nulls last),'[]')from units u),
 'sections',(select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('result',case when not exists(select 1 from sections c where c.section='other' and c.cost<>0) then revenue-cost end,'margin_percent',case when revenue<>0 and not exists(select 1 from sections c where c.section='other' and c.cost<>0) then (revenue-cost)/revenue*100 end)),'[]')from sections s),
 'transactions',case when p_unit is not null then(select coalesce(jsonb_agg(to_jsonb(d)),'[]')from details d)else '[]'::jsonb end,
 'analysis_inputs',(select coalesce(jsonb_agg(to_jsonb(a) order by unit_id,business_group),'[]') from analysis_inputs a),
 'saw_breakdown',(select case when count(*)>0 then jsonb_build_object(
 'revenue',coalesce(sum(amount)filter(where kind='revenue'),0),
 'material_revenue',coalesce(sum(amount)filter(where kind='revenue' and original?'_humla_saw_chip'),0),
 'material_tons',coalesce(sum((original#>>'{_humla_saw_chip,tons}')::numeric)filter(where kind='revenue' and original?'_humla_saw_chip'),0),
 'material_rate',(select chip_rate_per_ton from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant),
 'cost',coalesce(sum(amount)filter(where kind='cost'),0),
 'management_cost',coalesce(sum(amount)filter(where kind='cost' and category='management'),0),
 'other_cost',coalesce(sum(amount)filter(where kind='cost' and category is distinct from 'management'),0),
 'truck_charge',coalesce(sum((original#>>'{_humla_saw_activity,hours}')::numeric*(original#>>'{_humla_saw_activity,truck_hour_rate}')::numeric)
 filter(where kind='revenue' and original#>>'{_humla_saw_activity,reason}'='article_hour_split' and original#>>'{_humla_saw_activity,branch}'='saw'),0),
 'material_rows',coalesce(jsonb_agg(jsonb_build_object('id',fact_id,'date',occurred_on,'tons',original#>'{_humla_saw_chip,tons}',
 'amount',amount,'source',original#>>'{_humla_saw_chip,source}','ticket',original#>>'{_humla_saw_chip,ticket_number}',
 'order',coalesce(original#>>'{_humla_saw_chip,order_number}',original#>>'{_humla_saw_chip,order_numbers}')) order by occurred_on,fact_id)
 filter(where kind='revenue' and original?'_humla_saw_chip'),'[]'::jsonb)) end
 from facts where unit_id=(select unit_id from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant)),
 'driver_count',private.hub_kpi_driver_count_v1(p_tenant,(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant),
  p_from,p_to,p_months,array(select distinct original->>'time_report_id' from facts where source='TransPA' and original->>'time_report_id' is not null),
  (select coalesce(jsonb_agg(jsonb_build_object('fact_id',fact_id,'vehicle',vehicle,'amount',amount)),'[]')
   from facts where source='NEXT' and kind='cost' and category='personnel' and vehicle is not null)),
 'generation',(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant),
 'synced_at',(select synced_at from private.hub_kpi_report_state where tenant_id=p_tenant)) into output;
 
if p_user='00000000-0000-0000-0000-000000000030'::uuid then return output; end if;
time_basis:=private.hub_foreman_hours_v1(p_tenant,p_from,p_to,p_user,p_unit,p_months,p_group);
time_to:=case when(time_basis->>'shared_crane_time')::boolean then(time_basis->>'through')::date else least((time_basis->>'transpa_through')::date,(time_basis->>'next_through')::date)end;
if time_to is not null and time_to<p_to then
time_basis:=private.hub_foreman_hours_v1(p_tenant,p_from,time_to,p_user,p_unit,p_months,p_group);
end if;
hours:=(time_basis->>'worked_hours')::numeric;
select coalesce(sum(f.amount)filter(where f.kind='revenue'),0),coalesce(sum(f.amount)filter(where f.kind='cost'),0)into time_revenue,time_cost
from private.hub_transport_leader_facts_v2(p_tenant,p_from,coalesce(time_to,p_to),p_user)f
where(p_unit is null or f.unit_id=p_unit)and(p_group is null or coalesce(nullif(f.business_group,''),'Ej klassificerat')=p_group)
and(p_months is null or extract(month from f.occurred_on)::int=any(p_months));
select count(*)into covered from jsonb_to_recordset(coalesce(time_basis->'units','[]'))u(unit_id uuid,hours numeric)
where u.hours>0 and exists(select 1 from jsonb_to_recordset(output->'units')r(unit_id uuid)where r.unit_id=u.unit_id);
output:=output||jsonb_build_object('area_kpis',private.hub_foreman_area_kpis_v1(output,true)||jsonb_build_object(
'worked_hours',hours,'verified_hours',hours,'covered_units',covered,'hours_complete',false,
'revenue_per_hour',case when hours>0 then time_revenue/hours end,
'cost_per_hour',case when hours>0 then time_cost/hours end,
'result_per_hour',case when hours>0 then(time_revenue-time_cost)/hours end,
'time_from',p_from,'time_to',time_to,'time_sources',time_basis-'units',
'time_revenue',time_revenue,'time_cost',time_cost,'time_result',time_revenue-time_cost));

 output:=private.hub_foreman_mileage_v1(p_tenant,output,p_user,p_months,p_group);
 return private.hub_foreman_time_cards_v1(p_tenant,output,p_user,p_months,p_group);
end $function$;

CREATE OR REPLACE FUNCTION public.hub_kpi_overview_months_v1(p_tenant_id uuid, p_fiscal_year integer, p_selected_months integer[], p_cost_center text DEFAULT NULL::text, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
 SET statement_timeout TO '45s'
AS $function$
#variable_conflict use_variable
declare generation uuid;revision integer;months integer[];report jsonb;center text:=coalesce(p_cost_center,'');
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')then raise exception 'KPI access required'using errcode='42501';end if;
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>4000 or length(center)>100 then raise exception 'Ogiltigt rapporturval';end if;
 p_filters:=private.hub_kpi_ytd_filters_v1(p_fiscal_year,p_filters);
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);
 select active_generation,correction_revision into generation,revision from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 select c.report into report from private.hub_kpi_overview_cache_v1 c where c.tenant_id=p_tenant_id and c.generation_id=generation and c.revision=revision and c.fiscal_year=p_fiscal_year and c.months=months and c.center=center and c.filters=p_filters and c.report?'driver_count';
 if found then return report;end if;
 if not pg_try_advisory_xact_lock(hashtextextended(concat_ws(':','kpi-overview',p_tenant_id,generation,revision,p_fiscal_year,months,center,p_filters),0))then raise exception 'Rapporten förbereds redan. Försök igen om en stund.'using errcode='55P03';end if;
 report:=private.hub_kpi_overhead_projection_v1(p_tenant_id,p_fiscal_year,months,
 case when p_cost_center is null then p_filters else p_filters||jsonb_build_object('cost_center',p_cost_center)end,
 private.hub_kpi_mapped_units_projection_v1(p_tenant_id,private.hub_kpi_prepared_overview_v1(p_tenant_id,p_fiscal_year,months,p_cost_center,p_filters)));
 update private.hub_kpi_overview_cache_v1 c set report=report,created_at=now()
 where c.tenant_id=p_tenant_id and c.generation_id=generation and c.revision=revision and c.fiscal_year=p_fiscal_year
 and c.months=months and c.center=center and c.filters=p_filters;
 if not found then
  insert into private.hub_kpi_overview_cache_v1(tenant_id,generation_id,revision,fiscal_year,months,center,filters,report)
  values(p_tenant_id,generation,revision,p_fiscal_year,months,center,p_filters,report) on conflict do nothing;
 end if;
 return report;
end $function$;
