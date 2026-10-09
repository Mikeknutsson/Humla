-- Evaluate summaries once, avoid full ledger payloads and per-asset repeated scans.
create or replace function private.hub_fleet_kpi_v1(p_tenant uuid,p_year integer,p_months integer[],p_asset uuid default null,p_department text default null)
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='15s' as $$
declare output jsonb;generation uuid;today date:=(now() at time zone 'Europe/Stockholm')::date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'fleet.read') then raise exception 'Fordonsbehörighet saknas' using errcode='42501';end if;
 if p_year is null or p_year not between 2001 and 2100 or coalesce(cardinality(p_months),0)=0 or exists(select 1 from unnest(p_months)m where m is null or m not between 1 and 12) then raise exception 'Ogiltig period';end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant;
 with all_assets as materialized(select o.id,o.data from public.hub_objects o where o.tenant_id=p_tenant and o.object_type='Vehicle' and public.hub_resolve_canonical_object_v1(p_tenant,o.id)=o.id),
 assets as materialized(select * from all_assets where (p_asset is null or id=p_asset) and (p_department is null or coalesce(data#>>'{department,title}','Ej angiven')=p_department)),
 identity_candidates as materialized(select distinct k.identity_type,k.identity_value,public.hub_resolve_canonical_object_v1(p_tenant,k.object_id) id
 from public.hub_identity_keys k where k.tenant_id=p_tenant and k.confidence=1 and k.identity_type in ('registration_number','vehicle_registration','transpa_vehicle_id')),
 identities as materialized(select case when identity_type='transpa_vehicle_id' then 'time' else 'cost' end kind,identity_value,(array_agg(distinct id))[1] id
 from identity_candidates group by 1,2 having count(distinct id)=1),
 months as materialized(select dt::date df,least((dt+interval '1 month'-interval '1 day')::date,today) dt
 from generate_series(make_date(p_year,9,1)::timestamp,make_date(p_year+1,8,1)::timestamp,interval '1 month') dt where extract(month from dt)::int=any(p_months) and dt::date<=today),
 previous_months as materialized(select (df-interval '1 year')::date df,(dt-interval '1 year')::date dt from months),
 facts as materialized(select f.fact_id,f.occurred_on,f.amount,f.category,f.source,f.description,f.account,f.file_name,f.row_number,f.vehicle,(f.original#>>'{_humla_fuel,quantity_liters}')::numeric liters,i.id asset_id,
 case when f.category='fixed' and f.account in ('5612','5622') then 'insurance_tax' when f.category='fixed' and f.account='5615' then 'leasing' when f.category='fixed' and f.account in ('8410','8422') then 'interest' when f.category='fixed' and f.account='6950' then 'fees' else f.category end component
 from private.hub_kpi_prepared_facts f left join identities i on i.kind='cost' and i.identity_value=f.vehicle
 where f.tenant_id=p_tenant and f.generation_id=generation and f.fiscal_year in (p_year,p_year-1) and f.kind='cost' and f.category<>'personnel' and (exists(select 1 from months m where f.occurred_on between m.df and m.dt) or exists(select 1 from previous_months m where f.occurred_on between m.df and m.dt))),
 current_facts as materialized(select * from facts f where exists(select 1 from months m where f.occurred_on between m.df and m.dt)),
 fleet_costs as materialized(select f.* from current_facts f join assets a on a.id=f.asset_id where f.category in ('fuel','service_repair','fixed','depreciation')),
 cost_summary as materialized(select asset_id,sum(amount) cost,sum(amount) filter(where category='fuel') fuel,sum(amount) filter(where category='service_repair') service_repair,
 sum(amount) filter(where category='fixed') fixed,sum(amount) filter(where category='depreciation') depreciation,
 count(*) cost_rows,count(*) filter(where category='service_repair') repair_rows,
 case when bool_and(source='Piusi' or amount=0) filter(where category='fuel') then sum(liters) filter(where category='fuel') end liters,
 min(occurred_on) first_cost_date,max(occurred_on) last_cost_date from fleet_costs group by 1),
 previous_cost as materialized(select f.asset_id,sum(f.amount) cost from facts f where f.category in ('fuel','service_repair','fixed','depreciation') and exists(select 1 from previous_months m where f.occurred_on between m.df and m.dt) group by 1),
 meters as materialized(select a.id,m.df,m.dt,case when a.data->>'odometer_type'='K_OT_HOURS' then 'engine_hours' else 'odometer_km' end meter_type,
 case when a.data->>'odometer_type'='K_OT_HOURS' then private.hub_fleet_meter_usage_v1(p_tenant,a.id,'engine_hours',m.df,m.dt)
 else coalesce(d.estimate,private.hub_fleet_meter_usage_v1(p_tenant,a.id,'odometer_km',m.df,m.dt)) end estimate
 from assets a cross join months m left join private.hub_kpi_prepared_month_distance d on d.generation_id=generation and d.tenant_id=p_tenant and d.vehicle_id=a.id and d.date_from=m.df and d.date_to=m.dt),
 usage as(select id,max(meter_type) meter_type,count(*) months,count(*) filter(where coalesce(estimate->>'distance_km',estimate->>'value') is null) missing_months,
 case when bool_and(coalesce(estimate->>'distance_km',estimate->>'value') is not null) then sum(coalesce(estimate->>'distance_km',estimate->>'value')::numeric) end usage,
 bool_or(estimate->>'basis'='interpolated') interpolated from meters group by 1),
 time_first as materialized(select i.id,min(d.work_date) first_date from private.hub_kpi_prepared_daily d join identities i on i.kind='time' and i.identity_value=d.vehicle_id
 where d.tenant_id=p_tenant and d.generation_id=generation group by 1),
 all_time_rows as materialized(select i.id,d.* from private.hub_kpi_prepared_daily d join identities i on i.kind='time' and i.identity_value=d.vehicle_id
 where d.tenant_id=p_tenant and d.generation_id=generation and exists(select 1 from months m where d.work_date between m.df and m.dt)),
 time_rows as materialized(select t.* from all_time_rows t join assets a on a.id=t.id),
 time_summary as materialized(select id,sum(reported_vehicle_hours) hours,sum(time_reports) reports from time_rows group by 1),
 capacity as materialized(select a.id,count(*) filter(where extract(isodow from working_date) between 1 and 5 and not public.hub_is_swedish_public_holiday(working_date::date))*coalesce((select s.vehicle_capacity_hours_per_day from public.kpi_settings s where s.tenant_id=p_tenant),8) capacity
 from assets a join time_first t on t.id=a.id cross join months m cross join lateral generate_series(greatest(m.df,t.first_date)::timestamp,m.dt::timestamp,interval '1 day') working_date group by 1),
 maintenance as materialized(select r.asset_id,count(*) filter(where r.relation_type='fault' and coalesce(r.metadata->>'status','open') not in ('closed','resolved')) open_faults,
 jsonb_agg(jsonb_build_object('id',r.id,'type',r.relation_type,'status',r.metadata->>'status','due',r.metadata->>'due_at','title',coalesce(r.metadata->>'title',o.data->>'title',o.data->>'description','Uppgift saknas')) order by r.created_at desc) records
 from public.hub_fleet_asset_relations r join assets a on a.id=r.asset_id left join public.hub_objects o on o.tenant_id=p_tenant and o.id=r.related_object_id
 where r.tenant_id=p_tenant and r.relation_type in ('service','inspection','fault') and r.valid_from<=now() and (r.valid_to is null or r.valid_to>now()) group by 1),
 rows as materialized(select a.id,a.data,c.cost,c.fuel,c.service_repair,c.fixed,c.depreciation,c.cost_rows,c.repair_rows,c.liters,c.first_cost_date,c.last_cost_date,p.cost previous_cost,
 round((c.cost-p.cost)/nullif(p.cost,0)*100,1) change_pct,u.meter_type,u.usage,u.missing_months,u.interpolated,t.hours reported_hours,cap.capacity,round(t.hours/nullif(cap.capacity,0)*100,1) utilization,
 round(c.cost/nullif(case when u.meter_type='odometer_km' then u.usage/10 else u.usage end,0),2) cost_per_unit,
 round(c.fuel/nullif(case when u.meter_type='odometer_km' then u.usage/10 else u.usage end,0),2) fuel_per_unit,
 round(c.liters/nullif(case when u.meter_type='odometer_km' then u.usage/10 else u.usage end,0),2) liters_per_unit,mt.open_faults,mt.records maintenance
 from assets a left join cost_summary c on c.asset_id=a.id left join previous_cost p on p.asset_id=a.id left join usage u on u.id=a.id left join time_summary t on t.id=a.id left join capacity cap on cap.id=a.id left join maintenance mt on mt.asset_id=a.id)
 select jsonb_build_object('period',jsonb_build_object('year',p_year,'months',p_months,'through',today),'sync_at',(select synced_at from private.hub_kpi_report_state where tenant_id=p_tenant),
 'departments',(select coalesce(jsonb_agg(name order by name),'[]') from(select distinct coalesce(data#>>'{department,title}','Ej angiven') name from all_assets)x),
 'summary',(select jsonb_build_object('assets',count(*),'cost',round(sum(cost),2),'fuel',round(sum(fuel),2),'service_repair',round(sum(service_repair),2),'fixed',round(sum(fixed),2),'depreciation',round(sum(depreciation),2),
 'cost_assets',count(cost),'meter_assets',count(usage),'time_assets',count(reported_hours),'maintenance_assets',count(maintenance),'reported_hours',round(sum(reported_hours),2),
 'utilization',round(sum(reported_hours)/nullif(sum(capacity) filter(where reported_hours is not null),0)*100,1)) from rows),
 'assets',coalesce((select jsonb_agg((to_jsonb(r)-'data')||jsonb_build_object('registration',data->>'registration_number','description',data->>'description','model',concat_ws(' ',data->>'make',data->>'model'),'department',coalesce(data#>>'{department,title}','Ej angiven')) order by data->>'registration_number') from rows r),'[]'),
 'components',(select coalesce(jsonb_agg(x order by component),'[]') from(select component,round(sum(amount),2) amount,count(*) rows from fleet_costs group by 1)x),
 'monthly',(select coalesce(jsonb_agg(x order by date),'[]') from(select m.df date,round(sum(f.amount),2) cost,round(sum(f.amount) filter(where f.category='fuel'),2) fuel,round(sum(f.amount) filter(where f.category='service_repair'),2) service_repair,count(f.fact_id) rows from months m left join fleet_costs f on f.occurred_on between m.df and m.dt group by 1)x),
 'coverage',(select jsonb_build_object('unlinked_cost',round(sum(amount) filter(where asset_id is null and category in ('fuel','service_repair','fixed','depreciation')),2),
 'unlinked_rows',count(*) filter(where asset_id is null and category in ('fuel','service_repair','fixed','depreciation')),
 'other_linked_cost',round(sum(f.amount) filter(where a.id is not null and category not in ('fuel','service_repair','fixed','depreciation')),2),
 'other_linked_rows',count(*) filter(where a.id is not null and category not in ('fuel','service_repair','fixed','depreciation'))) from current_facts f left join assets a on a.id=f.asset_id),
 'evidence_count',(select count(*) from fleet_costs where p_asset is not null),
 'evidence',case when p_asset is null then '[]'::jsonb else (select coalesce(jsonb_agg(x order by date desc),'[]') from(select fact_id id,occurred_on date,amount,component,source,description,account,file_name,row_number from fleet_costs order by occurred_on desc,fact_id limit 5000)x) end,
 'meter_evidence',case when p_asset is null then '[]'::jsonb else (select coalesce(jsonb_agg(jsonb_build_object('from',df,'to',dt,'type',meter_type,'estimate',estimate) order by df),'[]') from meters) end,
 'time_evidence',case when p_asset is null then '[]'::jsonb else (select coalesce(jsonb_agg(jsonb_build_object('date',work_date,'hours',reported_vehicle_hours,'reports',time_reports) order by work_date),'[]') from time_rows) end) into output;
 return output;
end $$;
