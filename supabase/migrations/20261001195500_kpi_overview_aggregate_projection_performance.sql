-- Keep original financial facts in drilldown; Overview only materializes the fields it aggregates.
CREATE OR REPLACE FUNCTION private.hub_kpi_classified_facts_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb, cost_center text, cost_center_name text, classification_source jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with facts as materialized(select * from private.hub_kpi_financial_facts_v1(p_tenant_id,p_from,p_to)),
 center_names as materialized(select cost_center,min(cost_center_name) name from public.kpi_project_classification_periods where tenant_id=p_tenant_id group by cost_center),
 registry as materialized(select * from public.kpi_project_classification_periods where tenant_id=p_tenant_id and valid_from<=p_to and (valid_to is null or valid_to>=p_from))
 select f.fact_id,f.occurred_on,f.kind,f.amount,f.category,f.project,f.vehicle,f.unit_id,f.unit_name,
  case when f.original#>>'{_humla_distribution,status}' in ('allocated','no_eligible_units') then f.business_group when nullif(f.original#>>'{_humla_assignment,group}','') is not null then f.business_group when own_group.has_group then f.business_group when explicit_group.has_group then f.business_group
   when cc.center_count>1 or bg.group_count>1 then 'Ej klassificerat' else coalesce(bg.group_name,f.business_group) end,
  f.source,f.description,f.account,f.file_name,f.row_number,f.original,
  coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),article.cost_center,nullif(f.original->>'_humla_cost_center',''),case when cc.center_count=1 then cc.code else 'unclassified' end),
  case when coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),nullif(f.original->>'_humla_cost_center','')) is not null then coalesce((select r.name from center_names r where r.cost_center=coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),f.original->>'_humla_cost_center')),f.original->>'_humla_cost_center') when article.cost_center is not null then coalesce((select r.name from center_names r where r.cost_center=article.cost_center),article.cost_center) when cc.center_count=1 then cc.name else 'Ej klassificerat' end,
  jsonb_build_object('registry_sources',cc.sources,'article_rule_id',article.id,'manual_assignment',f.original->'_humla_assignment','reason',case when f.original#>>'{_humla_assignment,cost_center}' is not null then 'manual_dated_assignment' when f.original->>'_humla_cost_center' is not null then 'verified_import_cost_center' when article.cost_center is not null then 'exact_dated_article_rule' when cc.center_count>1 then 'conflicting_cost_centers' when cc.center_count=0 then 'missing_cost_center' else 'exact_dated_reference' end)
 from facts f
 -- A verified dated article rule classifies revenue even without a vehicle/project.
 -- Vehicle identity and group matching retain their existing dated rules.
 left join lateral(
  select a.id,nullif(trim(a.cost_center),'') cost_center
  from public.kpi_workify_article_rules a
  where f.source='Workify' and a.tenant_id=p_tenant_id and a.enabled
   and a.article_number=coalesce(f.original->>'Artikelnummer','')
   and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)
  order by a.valid_from desc,a.id limit 1
 ) article on true
 left join lateral(
  select count(distinct r.cost_center) center_count,min(r.cost_center) code,min(r.cost_center_name) name,jsonb_agg(distinct r.source) sources
  from registry r where r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
  and (r.project_reference=f.project or f.vehicle=any(r.registrations) or (f.source='TransPA' and r.project_reference=f.original->>'employee_id'))
 ) cc on true
 left join lateral(
  with candidates as(select r.business_group,case when r.project_reference=f.project then 1 when f.vehicle=any(r.registrations) then 2 else 3 end priority
   from registry r where r.business_group is not null and r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
   and (r.project_reference=f.project or f.vehicle=any(r.registrations) or (f.source='TransPA' and r.project_reference=f.original->>'employee_id')))
  select count(distinct business_group) group_count,case when count(distinct business_group)=1 then min(business_group) end group_name from candidates where priority=(select min(priority) from candidates)
 ) bg on true
 left join lateral(select exists(select 1 from public.kpi_unit_periods p where p.tenant_id=p_tenant_id and p.unit_id=f.unit_id and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on) and nullif(p.payload->>'business_group_id','') is not null) has_group) own_group on true
 left join lateral(select exists(select 1 from public.kpi_project_business_groups p where p.tenant_id=p_tenant_id and p.project_reference=f.project and p.source='kpi_admin_dated' and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)) has_group) explicit_group on true;
$function$;

CREATE OR REPLACE FUNCTION private.hub_kpi_month_snapshot_v1(p_tenant_id uuid, p_fiscal_year integer, p_selected_months integer[], p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare output jsonb; months integer[]; fy_from date; fy_to date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501'; end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);
 fy_from:=make_date(p_fiscal_year,9,1);fy_to:=make_date(p_fiscal_year+1,8,31);
 with selected_facts as materialized(select fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,jsonb_build_object('time_report_id',original->'time_report_id','_humla_distribution',jsonb_build_object('status',original#>'{_humla_distribution,status}')) original from private.hub_kpi_month_facts_v1(p_tenant_id,p_fiscal_year,months,p_filters-'cost_center')),
 facts as materialized(select * from selected_facts where not(p_filters?'cost_center') or cost_center=p_filters->>'cost_center'),
 month_dates as(select m,make_date(case when m>=9 then p_fiscal_year else p_fiscal_year+1 end,m,1) dt from unnest(months) m),
 monthly as(select m,dt,coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost,count(f.fact_id) rows from month_dates left join facts f on date_trunc('month',f.occurred_on)::date=dt group by m,dt),
 cats as(select category,round(sum(amount),2) amount from facts where kind='cost' group by category),
 totals as(select coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost,
 coalesce(sum(amount) filter(where kind='revenue' and vehicle='LASTBIL'),0) hired,
 count(distinct vehicle) filter(where kind='revenue' and amount<>0 and vehicle not in ('LASTBIL','Ej fördelat')) vehicles from facts),
 groups as(select business_group key,business_group label,count(*) rows,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by business_group),
 units as(select coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') key,max(coalesce(unit_name,vehicle,'Ej fördelat')) label,count(*) rows,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by 1),
 unit_children as(select coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') unit_key,case when original#>>'{_humla_distribution,status}'='allocated' then 'shared:'||project else coalesce(vehicle,'project:'||project,'unassigned') end key,max(case when original#>>'{_humla_distribution,status}'='allocated' then 'Gemensam kostnad · '||project else coalesce(vehicle,project,'Ej fördelat') end) label,max(case when original#>>'{_humla_distribution,status}'<>'allocated' or original#>>'{_humla_distribution,status}' is null then vehicle end) vehicle,max(project) project,count(*) rows,round(coalesce(sum(amount)filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount)filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by 1,2),
 all_daily as materialized(select * from public.kpi_transpa_vehicle_time_daily_secure(p_tenant_id,date '2000-01-01',fy_to)),
 first_seen as(select vehicle_id,min(work_date) first_seen from all_daily group by vehicle_id),
 daily as materialized(select d.*,upper(trim(split_part(vehicle_name,' ',1))) reg from all_daily d
 where d.work_date between fy_from and fy_to and extract(month from d.work_date)::int=any(months)
 and upper(trim(split_part(vehicle_name,' ',1)))~'^[A-Z]{3}[0-9]{2}[A-Z0-9]$'
 and (p_filters='{}'::jsonb or exists(select 1 from facts f where f.source='TransPA' and f.occurred_on=d.work_date and f.vehicle=upper(trim(split_part(d.vehicle_name,' ',1)))))),
 vehicle_time_base as(select d.vehicle_id,max(d.reg) vehicle,sum(d.reported_vehicle_hours)::numeric hours,sum(d.time_reports) time_reports,min(fs.first_seen) first_seen from daily d join first_seen fs using(vehicle_id) group by d.vehicle_id),
 vehicle_time as(select v.*,(select count(*)::numeric from generate_series(greatest(fy_from,v.first_seen),fy_to,interval '1 day') d where extract(month from d)::int=any(months) and extract(isodow from d) between 1 and 5 and not public.hub_is_swedish_public_holiday(d::date)
 and (p_filters='{}'::jsonb or exists(select 1 from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and v.vehicle=any(r.registrations) and r.valid_from<=d::date and (r.valid_to is null or r.valid_to>=d::date) and (not(p_filters?'cost_center') or r.cost_center=p_filters->>'cost_center') and (not(p_filters?'group') or r.business_group=p_filters->>'group')))) * coalesce((select s.vehicle_capacity_hours_per_day::numeric from public.kpi_settings s where s.tenant_id=p_tenant_id),8) available_hours from vehicle_time_base v),
 time_totals as(select coalesce(sum(hours),0) hours,coalesce(sum(available_hours),0) available,count(*) vehicles from vehicle_time),
 next_daily as(select n.occurred_on work_date,upper(trim(n.vehicle_registration)) vehicle,sum(n.paid_hours) hours from public.kpi_import_rows n where n.tenant_id=p_tenant_id and n.is_valid and n.data_kind='next_historical_time' and n.occurred_on between fy_from and fy_to and extract(month from n.occurred_on)::int=any(months)
 and upper(trim(coalesce(n.description,'')))=any(array['K.CH','L.CH','MA','UEA','UEM','ÖT-1','ÖT-2','ÖT-3','ÖT-4','ÖT-5','ÖT-6']) and upper(trim(n.vehicle_registration))~'^[A-Z]{3}[0-9]{2}[A-Z0-9]$'
 and (p_filters='{}'::jsonb or exists(select 1 from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and r.project_reference=n.project_reference and r.valid_from<=n.occurred_on and (r.valid_to is null or r.valid_to>=n.occurred_on) and (not(p_filters?'cost_center') or r.cost_center=p_filters->>'cost_center') and (not(p_filters?'group') or r.business_group=p_filters->>'group')))
 group by 1,2),
 worked as(select tt.hours+coalesce((select sum(n.hours) from next_daily n where not exists(select 1 from daily d where d.work_date=n.work_date and d.reg=n.vehicle)),0) hours from time_totals tt),
 revenue_days as materialized(select f.occurred_on work_date,array_agg(distinct e.external_id) vehicle_ids from facts f join public.hub_transpa_entities e on e.tenant_id=p_tenant_id and e.entity_type='vehicle' and public.hub_normalize_vehicle_registration(e.payload->>'registrationNumber')=f.vehicle where f.kind='revenue' and f.amount<>0 group by f.occurred_on),
 eligible_time as materialized(select distinct original->>'time_report_id' report_id from facts where source='TransPA'),
 driver_time as(select t.employee_id,t.work_hours,coalesce(t.transpa_vehicle_ids ?| rd.vehicle_ids,false) productive
 from public.kpi_transpa_time_facts t left join revenue_days rd on rd.work_date=t.work_date
 where t.tenant_id=p_tenant_id and t.work_date between fy_from and fy_to and extract(month from t.work_date)::int=any(months)
 and (p_filters='{}'::jsonb or t.time_report_id::text in(select report_id from eligible_time))),
 drivers as(select employee_id driver,employee_id,sum(work_hours)::numeric total_hours,coalesce(sum(work_hours) filter(where productive),0)::numeric productive_hours,coalesce(sum(work_hours) filter(where not productive),0)::numeric unclassified_hours from driver_time group by employee_id),
 driver_totals as(select coalesce(sum(total_hours),0) hours,coalesce(sum(productive_hours),0) productive,coalesce(sum(unclassified_hours),0) unclassified from drivers),
 vehicles as(select coalesce(f.vehicle,'Ej fördelat') vehicle,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result,round(coalesce(sum(amount) filter(where category='fuel' and kind='cost'),0),2) fuel_cost,round(coalesce(sum(amount) filter(where source='TransPA'),0),2) personnel_cost from facts f group by f.vehicle)
 select jsonb_build_object(
 'hub_contract_version','fiscal-months-v1','period',jsonb_build_object('fiscal_year',p_fiscal_year,'selected_months',months,'from',fy_from,'to',fy_to),'filters',p_filters,
 'coverage',(select jsonb_build_object('revenue_months',coalesce(jsonb_agg(m)filter(where revenue_rows>0),'[]'),'cost_months',coalesce(jsonb_agg(m)filter(where next_rows>0),'[]'))from(select m,count(f.fact_id)filter(where f.source='Workify') revenue_rows,count(f.fact_id)filter(where f.source='NEXT')next_rows from unnest(months)m left join selected_facts f on extract(month from f.occurred_on)::int=m group by m)x),
 'metrics',jsonb_build_object('revenue',round(t.revenue,2),'total_cost',round(t.cost,2),'result',round(t.revenue-t.cost,2),'margin_pct',round((t.revenue-t.cost)/nullif(t.revenue,0)*100,2),'revenue_per_vehicle',round(t.revenue/nullif(t.vehicles,0),2),'diesel_share',round(coalesce((select amount from cats where category='fuel'),0)/nullif(t.revenue,0)*100,2),'vehicle_utilization',round(tt.hours/nullif(tt.available,0)*100,1)),
 'components',(select jsonb_build_object('next_total_cost',round(coalesce(sum(amount) filter(where source='NEXT'),0),2),'transpa_personnel_cost',round(coalesce(sum(amount) filter(where source='TransPA'),0),2),'depreciation_cost',round(coalesce(sum(amount) filter(where kind='cost' and category='depreciation'),0),2)) from facts),
 'monthly',(select jsonb_agg(jsonb_build_object('month',m,'period_start',dt,'period_end',(dt+interval '1 month'-interval '1 day')::date,'revenue',round(revenue,2),'cost',round(cost,2),'result',round(revenue-cost,2),'rows',rows) order by dt) from monthly),
 'business_groups',coalesce((select jsonb_agg(to_jsonb(g) order by label) from groups g),'[]'),
 'group_options',(select jsonb_agg(name order by name)from(select name from public.kpi_business_groups where tenant_id=p_tenant_id and enabled union select business_group from public.kpi_project_classification_periods where tenant_id=p_tenant_id and business_group is not null union select 'Ej klassificerat') names),
 'economic_units',coalesce((select jsonb_agg(to_jsonb(u)||jsonb_build_object('children',coalesce((select jsonb_agg(to_jsonb(c) order by label)from unit_children c where c.unit_key=u.key),'[]')) order by label) from units u),'[]'),
 'cost_categories',coalesce((select jsonb_object_agg(category,amount) from cats),'{}'),
 'vehicles',coalesce((select jsonb_agg(to_jsonb(v)||jsonb_build_object('occupied_hours',vt.hours,'available_hours',vt.available_hours,'utilization',round(vt.hours/nullif(vt.available_hours,0)*100,1),'revenue_per_hour',round(v.revenue/nullif(vt.hours,0),2)) order by v.vehicle) from vehicles v left join vehicle_time vt using(vehicle)),'[]'),
 'drivers',coalesce((select jsonb_agg(to_jsonb(d)) from drivers d),'[]'),'unmapped_accounts','[]'::jsonb,
 'unclassified_summary',(select jsonb_build_object('revenue',round(coalesce(sum(amount) filter(where kind='revenue'),0),2),'cost',round(coalesce(sum(amount) filter(where kind='cost'),0),2),'rows',count(*)) from selected_facts where cost_center='unclassified'),
 'quality',(select jsonb_build_object('total_rows',count(*),'valid_rows',count(*),'rows_without_vehicle',count(*) filter(where vehicle is null),'rows_without_employee',0,'rows_without_account_mapping',0,'basis','Hub authoritative financial facts') from facts),
 'transpa_vehicle_time',jsonb_build_object('reported_hours',round(tt.hours,2),'available_hours',round(tt.available,2),'vehicle_count',tt.vehicles,'utilization',round(tt.hours/nullif(tt.available,0)*100,1),'vehicles',coalesce((select jsonb_agg(to_jsonb(v)||jsonb_build_object('occupied_hours',hours,'utilization',round(hours/nullif(available_hours,0)*100,1))) from vehicle_time v),'[]')),
 'efficiency',jsonb_build_object('worked_hours',round(w.hours,2),'revenue',round(t.revenue,2),'own_revenue',round(t.revenue-t.hired,2),'hired_revenue',round(t.hired,2),'revenue_per_worked_hour',round((t.revenue-t.hired)/nullif(w.hours,0),2)),
 'hired_capacity',jsonb_build_object('total_revenue',round(t.revenue,2),'hired_revenue',round(t.hired,2),'hired_share_percent',round(t.hired/nullif(t.revenue,0)*100,2)),
 'driver_productivity',jsonb_build_object('total_hours',round(d.hours,2),'productive_hours',round(d.productive,2),'unclassified_hours',round(d.unclassified,2),'productive_percent',round(d.productive/nullif(d.hours,0)*100,1),'drivers',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('productive_percent',round(productive_hours/nullif(total_hours,0)*100,1))) from drivers x),'[]')),
 'cost_efficiency',coalesce((select jsonb_object_agg(category||'_cost_per_hour',round(amount/nullif(w.hours,0),2)) from cats),'{}')||jsonb_build_object('worked_hours',round(w.hours,2),'total_cost_per_hour',round(t.cost/nullif(w.hours,0),2),'result_per_hour',round((t.revenue-t.cost)/nullif(w.hours,0),2),'direct_cost_per_hour',null,'common_cost_per_hour',null,'overhead_cost_per_hour',null,'contribution_per_hour',null),
 'personnel_basis','TransPA-tid × Hub-schablon; inte verifierad löneexport',
 'reconciliation',jsonb_build_object('matches',t.revenue=(select sum(revenue) from monthly) and t.cost=(select sum(cost) from monthly),'vehicle_rows_match',abs(round(t.revenue,2)-(select coalesce(sum(revenue),0) from vehicles))<=0.01*(select count(*) from vehicles) and abs(round(t.cost,2)-(select coalesce(sum(cost),0) from vehicles))<=0.01*(select count(*) from vehicles),'source','Hub authoritative classified facts, exact selected months')
 ) into output from totals t cross join time_totals tt cross join worked w cross join driver_totals d;
 return output;
end $function$;

alter function private.hub_kpi_month_snapshot_v1(uuid,integer,integer[],jsonb) set work_mem='16MB';
