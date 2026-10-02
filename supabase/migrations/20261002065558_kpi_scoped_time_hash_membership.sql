CREATE OR REPLACE FUNCTION private.hub_kpi_month_snapshot_v1(p_tenant_id uuid, p_fiscal_year integer, p_selected_months integer[], p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET work_mem TO '16MB'
AS $function$
declare output jsonb; months integer[]; fy_from date; fy_to date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501'; end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);
 fy_from:=make_date(p_fiscal_year,9,1);fy_to:=make_date(p_fiscal_year+1,8,31);
 with selected_facts as materialized(select fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,jsonb_build_object('time_report_id',original->'time_report_id','_humla_distribution',jsonb_build_object('status',original#>'{_humla_distribution,status}')) original from private.hub_kpi_month_facts_v1(p_tenant_id,p_fiscal_year,months,p_filters-'cost_center')),
 facts as materialized(select * from selected_facts where not(p_filters?'cost_center') or cost_center=any(string_to_array(p_filters->>'cost_center',','))),
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
 and (p_filters='{}'::jsonb or (d.work_date,upper(trim(split_part(d.vehicle_name,' ',1)))) in(select f.occurred_on,f.vehicle from facts f where f.source='TransPA'))),
 vehicle_time_base as(select d.vehicle_id,max(d.reg) vehicle,sum(d.reported_vehicle_hours)::numeric hours,sum(d.time_reports) time_reports,min(fs.first_seen) first_seen from daily d join first_seen fs using(vehicle_id) group by d.vehicle_id),
 vehicle_time as(select v.*,(select count(*)::numeric from generate_series(greatest(fy_from,v.first_seen),fy_to,interval '1 day') d where extract(month from d)::int=any(months) and extract(isodow from d) between 1 and 5 and not public.hub_is_swedish_public_holiday(d::date)
 and (p_filters='{}'::jsonb or exists(select 1 from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and v.vehicle=any(r.registrations) and r.valid_from<=d::date and (r.valid_to is null or r.valid_to>=d::date) and (not(p_filters?'cost_center') or r.cost_center=any(string_to_array(p_filters->>'cost_center',','))) and (not(p_filters?'group') or r.business_group=p_filters->>'group')))) * coalesce((select s.vehicle_capacity_hours_per_day::numeric from public.kpi_settings s where s.tenant_id=p_tenant_id),8) available_hours from vehicle_time_base v),
 time_totals as(select coalesce(sum(hours),0) hours,coalesce(sum(available_hours),0) available,count(*) vehicles from vehicle_time),
 next_daily as(select n.occurred_on work_date,upper(trim(n.vehicle_registration)) vehicle,sum(n.paid_hours) hours from public.kpi_import_rows n where n.tenant_id=p_tenant_id and n.is_valid and n.data_kind='next_historical_time' and n.occurred_on between fy_from and fy_to and extract(month from n.occurred_on)::int=any(months)
 and upper(trim(coalesce(n.description,'')))=any(array['K.CH','L.CH','MA','UEA','UEM','ÖT-1','ÖT-2','ÖT-3','ÖT-4','ÖT-5','ÖT-6']) and upper(trim(n.vehicle_registration))~'^[A-Z]{3}[0-9]{2}[A-Z0-9]$'
 and (p_filters='{}'::jsonb or exists(select 1 from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and r.project_reference=n.project_reference and r.valid_from<=n.occurred_on and (r.valid_to is null or r.valid_to>=n.occurred_on) and (not(p_filters?'cost_center') or r.cost_center=any(string_to_array(p_filters->>'cost_center',','))) and (not(p_filters?'group') or r.business_group=p_filters->>'group')))
 group by 1,2),
 worked as(select tt.hours+coalesce((select sum(n.hours) from next_daily n where not exists(select 1 from daily d where d.work_date=n.work_date and d.reg=n.vehicle)),0) hours from time_totals tt),
 revenue_days as materialized(select f.occurred_on work_date,array_agg(distinct e.external_id) vehicle_ids from facts f join public.hub_transpa_entities e on e.tenant_id=p_tenant_id and e.entity_type='vehicle' and public.hub_normalize_vehicle_registration(e.payload->>'registrationNumber')=f.vehicle where f.kind='revenue' and f.amount<>0 group by f.occurred_on),
 eligible_time as materialized(select distinct original->>'time_report_id' report_id from facts where source='TransPA'),
 selected_time as materialized(select tenant_id,time_report_id,employee_id,work_date,work_hours,transpa_vehicle_ids from public.kpi_transpa_time_facts where tenant_id=p_tenant_id and work_date between fy_from and fy_to and extract(month from work_date)::int=any(months)),
 driver_time as(select t.employee_id,t.work_hours,coalesce(t.transpa_vehicle_ids ?| rd.vehicle_ids,false) productive
 from selected_time t left join revenue_days rd on rd.work_date=t.work_date
 where t.tenant_id=p_tenant_id and t.work_date between fy_from and fy_to and extract(month from t.work_date)::int=any(months)
 and (p_filters='{}'::jsonb or t.time_report_id::text in(select report_id from eligible_time))),
 drivers as(select employee_id driver,employee_id,sum(work_hours)::numeric total_hours,coalesce(sum(work_hours) filter(where productive),0)::numeric productive_hours,coalesce(sum(work_hours) filter(where not productive),0)::numeric unclassified_hours from driver_time group by employee_id),
 driver_totals as(select coalesce(sum(total_hours),0) hours,coalesce(sum(productive_hours),0) productive,coalesce(sum(unclassified_hours),0) unclassified from drivers),

 unit_versions as materialized(
 select u.id::text unit_key,v.valid_from,v.valid_to,coalesce((v.payload->>'enabled')::boolean,u.enabled) enabled,
 coalesce(nullif(v.payload->>'main_vehicle',''),nullif(v.payload->>'name',''),u.name) main_vehicle,v.payload->>'business_group_id' group_id
 from public.kpi_units u join public.kpi_unit_periods v on v.tenant_id=u.tenant_id and v.unit_id=u.id where u.tenant_id=p_tenant_id
 union all select u.id::text,u.valid_from,u.valid_to,u.enabled,u.name,null from public.kpi_units u where u.tenant_id=p_tenant_id and not exists(select 1 from public.kpi_unit_periods v where v.tenant_id=u.tenant_id and v.unit_id=u.id)
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
 and (not(p_filters?'cost_center') or exists(select 1 from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and ud.main_vehicle=any(r.registrations) and r.valid_from<=ud.dt and (r.valid_to is null or r.valid_to>=ud.dt) and r.cost_center=any(string_to_array(p_filters->>'cost_center',','))))
 and (not(p_filters?'group') or exists(select 1 from public.kpi_business_groups g where g.tenant_id=p_tenant_id and g.id::text=ud.group_id and g.name=p_filters->>'group')
 or (ud.group_id is null and exists(select 1 from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and ud.main_vehicle=any(r.registrations) and r.valid_from<=ud.dt and (r.valid_to is null or r.valid_to>=ud.dt) and r.business_group=p_filters->>'group')))
 then coalesce((select s.vehicle_capacity_hours_per_day::numeric from public.kpi_settings s where s.tenant_id=p_tenant_id),8) else 0 end)::numeric available_hours
 from unit_days ud join (select d.reg,min(f.first_seen) first_seen from daily d join first_seen f using(vehicle_id) group by d.reg) fs on fs.reg=ud.main_vehicle group by ud.key),
 unit_distance_spans as materialized(select key,m,min(dt) df,max(dt) dt,case when count(distinct main_vehicle)=1 and bool_and(enabled) then max(main_vehicle) end registration from unit_days group by key,m),
 distance_manual as(select s.key,s.m,case when min(p.period_from)=s.df and max(p.period_to)=s.dt and sum(p.period_to-p.period_from+1)=s.dt-s.df+1 then sum(p.distance_km) end km
 from unit_distance_spans s left join public.kpi_vehicle_distance_periods p on p.tenant_id=p_tenant_id and p.registration=s.registration and p.period_from>=s.df and p.period_to<=s.dt group by s.key,s.m,s.df,s.dt),
 distance_assets as(select public.hub_normalize_vehicle_registration(data->>'registration_number') registration,(array_agg(id))[1] id from public.hub_objects where tenant_id=p_tenant_id and object_type='Vehicle' group by 1 having count(*)=1),
 distance_estimates as materialized(select s.key,s.m,private.hub_kpi_interpolated_distance_v1(p_tenant_id,a.id,s.df,s.dt) estimate from unit_distance_spans s join distance_assets a on a.registration=s.registration),
 distance_meters as(select key,m,(estimate->>'distance_km')::numeric km,estimate from distance_estimates),
 unit_distance as(select s.key,case when bool_and(coalesce(a.km,b.km) is not null) then sum(coalesce(a.km,b.km))/10 end distance_mil,
 count(*) filter(where coalesce(a.km,b.km) is null) missing_months,
 bool_or(a.km is null and b.estimate->>'basis'='interpolated') estimated,
 jsonb_agg(jsonb_build_object('month',s.m,'from',s.df,'to',s.dt,'distance_mil',coalesce(a.km,b.km)/10,'basis',case when a.km is not null then 'period_import' else coalesce(b.estimate->>'basis','missing') end,'measurement_basis',case when a.km is null then b.estimate end) order by s.df) distance_monthly
 from unit_distance_spans s left join distance_manual a using(key,m) left join distance_meters b using(key,m) group by s.key),
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
 'fuel_cost_per_mil',round(coalesce((c.categories->>'fuel')::numeric,0)/nullif(d.distance_mil,0),2),'fuel_liters_per_mil',null,
 'distance_basis',case when d.distance_mil is null then 'missing_complete_period' when d.estimated then 'main_vehicle_interpolated_period' else 'main_vehicle_exact_period' end,
 'distance_monthly',d.distance_monthly,'missing_distance_months',d.missing_months) performance
 from units u left join unit_categories c on c.unit_key=u.key left join unit_driver_time t on t.unit_key=u.key left join unit_occupied o on o.unit_key=u.key left join unit_capacity a on a.key=u.key left join unit_distance d on d.key=u.key),
 vehicles as(select coalesce(f.vehicle,'Ej fördelat') vehicle,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result,round(coalesce(sum(amount) filter(where category='fuel' and kind='cost'),0),2) fuel_cost,round(coalesce(sum(amount) filter(where source='TransPA'),0),2) personnel_cost from facts f group by f.vehicle)
 select jsonb_build_object(
 'hub_contract_version','fiscal-months-v1','period',jsonb_build_object('fiscal_year',p_fiscal_year,'selected_months',months,'from',fy_from,'to',fy_to),'filters',p_filters,
 'coverage',(select jsonb_build_object('revenue_months',coalesce(jsonb_agg(m)filter(where revenue_rows>0),'[]'),'cost_months',coalesce(jsonb_agg(m)filter(where next_rows>0),'[]'))from(select m,count(f.fact_id)filter(where f.source='Workify') revenue_rows,count(f.fact_id)filter(where f.source='NEXT')next_rows from unnest(months)m left join selected_facts f on extract(month from f.occurred_on)::int=m group by m)x),
 'metrics',jsonb_build_object('revenue',round(t.revenue,2),'total_cost',round(t.cost,2),'result',round(t.revenue-t.cost,2),'margin_pct',round((t.revenue-t.cost)/nullif(t.revenue,0)*100,2),'revenue_per_vehicle',round(t.revenue/nullif(t.vehicles,0),2),'diesel_share',round(coalesce((select amount from cats where category='fuel'),0)/nullif(t.revenue,0)*100,2),'vehicle_utilization',round(tt.hours/nullif(tt.available,0)*100,1)),
 'components',(select jsonb_build_object('next_total_cost',round(coalesce(sum(amount) filter(where source='NEXT'),0),2),'transpa_personnel_cost',round(coalesce(sum(amount) filter(where source='TransPA'),0),2),'depreciation_cost',round(coalesce(sum(amount) filter(where kind='cost' and category='depreciation'),0),2)) from facts),
 'monthly',(select jsonb_agg(jsonb_build_object('month',m,'period_start',dt,'period_end',(dt+interval '1 month'-interval '1 day')::date,'revenue',round(revenue,2),'cost',round(cost,2),'result',round(revenue-cost,2),'rows',rows) order by dt) from monthly),
 'business_groups',coalesce((select jsonb_agg(to_jsonb(g) order by label) from groups g),'[]'),
 'group_options',(select jsonb_agg(name order by name)from(select name from public.kpi_business_groups where tenant_id=p_tenant_id and enabled union select business_group from public.kpi_project_classification_periods where tenant_id=p_tenant_id and business_group is not null union select 'Ej klassificerat') names),
 'economic_units',coalesce((select jsonb_agg(to_jsonb(u)||p.performance||jsonb_build_object('children',coalesce((select jsonb_agg(to_jsonb(c) order by label)from unit_children c where c.unit_key=u.key),'[]')) order by label) from units u join unit_performance p using(key)),'[]'),
 'cost_categories',jsonb_build_object('personnel',0,'fuel',0,'service_repair',0,'depreciation',0,'fixed',0,'other',0,'material',0,'tipp_deponi',0,'hired',0)||coalesce((select jsonb_object_agg(category,amount) from cats),'{}'),
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
end $function$
;