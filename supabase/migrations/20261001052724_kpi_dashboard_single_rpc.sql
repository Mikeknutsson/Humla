create or replace function public.hub_kpi_dashboard_display_v1(p_tenant_id uuid,p_from date,p_to date,p_previous_from date default null,p_previous_to date default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare hub jsonb; legacy jsonb; result jsonb; prev jsonb; report jsonb; vehicle_rows jsonb; categories jsonb; derived jsonb; hours numeric; fuel numeric; personnel numeric; efficiency jsonb; vehicle_time jsonb;
begin
 -- Force access validation before calling existing Hub engines.
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 then raise exception 'Invalid period';end if;
 hub:=public.hub_kpi_transport_dashboard_v4(p_tenant_id,p_from,p_to);
 if p_previous_from is null and p_previous_to is null then p_previous_from:=(p_from-interval '1 year')::date;p_previous_to:=(p_to-interval '1 year')::date;end if;
 legacy:=public.kpi_transport_dashboard(p_tenant_id,p_from,p_to);
 report:=public.hub_kpi_analysis_v1(p_tenant_id,p_from,p_to);
 efficiency:=public.kpi_transport_efficiency(p_tenant_id,p_from,p_to);
 vehicle_time:=public.kpi_transpa_vehicle_time(p_tenant_id,p_from,p_to);
 hours:=coalesce((efficiency->>'worked_hours')::numeric,0);
 fuel:=coalesce((select (value->>'amount')::numeric from jsonb_array_elements(hub->'cost_categories') where value->>'category'='fuel'),0);
 personnel:=coalesce((select (value->>'amount')::numeric from jsonb_array_elements(hub->'cost_categories') where value->>'category'='personnel'),0)+(hub#>>'{components,transpa_personnel_cost}')::numeric;
 select jsonb_object_agg(cat,amt) into categories from (
  select value->>'category' cat,(value->>'amount')::numeric amt from jsonb_array_elements(hub->'cost_categories') where value->>'category' not in ('personnel','depreciation')
  union all select 'personnel',personnel union all select 'depreciation',coalesce((select (value->>'amount')::numeric from jsonb_array_elements(hub->'cost_categories') where value->>'category'='depreciation'),0)+(hub#>>'{components,depreciation_cost}')::numeric
 ) c;
 with f as (select * from private.hub_kpi_financial_facts_v1(p_tenant_id,p_from,p_to)), v as (
  select coalesce(vehicle,'Ej fördelat') vehicle,
   coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost,
   coalesce(sum(amount) filter(where kind='cost' and category='fuel'),0) fuel_cost,
   coalesce(sum(amount) filter(where source='TransPA'),0) personnel_cost,
   coalesce(sum(case when kind='revenue' then amount else -amount end),0) result
  from f group by vehicle
 ), t as (select value x from jsonb_array_elements(coalesce(vehicle_time->'vehicles','[]')))
 select coalesce(jsonb_agg(to_jsonb(v)||jsonb_build_object('occupied_hours',coalesce((t.x->>'occupied_hours')::numeric,0),'available_hours',coalesce((t.x->>'available_hours')::numeric,0),'utilization',(t.x->>'utilization')::numeric,
  'revenue_per_hour',case when (t.x->>'occupied_hours')::numeric>0 then round(v.revenue/(t.x->>'occupied_hours')::numeric,2) else null end) order by v.vehicle),'[]') into vehicle_rows
 from v left join t on t.x->>'vehicle'=v.vehicle;
 derived:=jsonb_build_object('diesel_share',case when (hub#>>'{metrics,revenue}')::numeric<>0 then round(fuel/(hub#>>'{metrics,revenue}')::numeric*100,2) else null end,
  'revenue_per_vehicle',case when jsonb_array_length(vehicle_rows)>0 then round((hub#>>'{metrics,revenue}')::numeric/nullif((select count(*) from jsonb_array_elements(vehicle_rows) r where r->>'vehicle' not in ('LASTBIL','Ej fördelat') and (r->>'revenue')::numeric<>0),0),2) else null end);
 if p_previous_from is not null and p_previous_to is not null then
  prev:=public.hub_kpi_transport_dashboard_v4(p_tenant_id,p_previous_from,p_previous_to);
  derived:=derived||jsonb_build_object('revenue_change_pct',case when (prev#>>'{metrics,revenue}')::numeric<>0 then round(((hub#>>'{metrics,revenue}')::numeric/(prev#>>'{metrics,revenue}')::numeric-1)*100,2) else null end);
 end if;
 result:=legacy||hub||jsonb_build_object('metrics',(legacy->'metrics')||(hub->'metrics')||derived,'vehicles',vehicle_rows,'cost_categories',categories,'business_groups',report->'groups','previous',prev,
  'repair_summary',(select jsonb_build_object('approved',coalesce(sum(amount) filter(where status='approved'),0),'pending',coalesce(sum(amount) filter(where status='pending_review'),0),'approved_count',count(*) filter(where status='approved'),'pending_count',count(*) filter(where status='pending_review')) from public.hub_fordonskontrollen_cost_outbox where tenant_id=p_tenant_id and occurred_on between p_from and p_to),
  'efficiency',efficiency,'transpa_vehicle_time',vehicle_time,'hired_capacity',public.kpi_hired_capacity_share(p_tenant_id,p_from,p_to),'driver_productivity',public.kpi_driver_productive_time(p_tenant_id,p_from,p_to),
  'cost_efficiency',coalesce((select jsonb_object_agg(key||'_cost_per_hour',case when hours>0 then round(value::numeric/hours,2) end) from jsonb_each_text(categories)),'{}')||jsonb_build_object('direct_cost_per_hour',null,'common_cost',null,'common_cost_per_hour',null,'overhead_cost_per_hour',null,'contribution_per_hour',null,'worked_hours',hours,'total_cost_per_hour',case when hours>0 then round((hub#>>'{metrics,total_cost}')::numeric/hours,2) end,'personnel_cost_per_hour',case when hours>0 then round(personnel/hours,2) end,'fuel_cost_per_hour',case when hours>0 then round(fuel/hours,2) end,'result_per_hour',case when hours>0 then round((hub#>>'{metrics,result}')::numeric/hours,2) end),
  'reconciliation',jsonb_build_object('source_revenue',hub#>'{metrics,revenue}','source_next_cost',hub#>'{components,next_total_cost}','detail_revenue',report#>'{summary,revenue}','detail_next_cost',report#>'{summary,next_cost}',
  'matches',hub#>'{metrics,revenue}'=report#>'{summary,revenue}' and hub#>'{components,next_total_cost}'=report#>'{summary,next_cost}'),
  'personnel_basis','TransPA-tid × Hub-schablon; inte verifierad löneexport');
 return result;
end $$;
revoke all on function public.hub_kpi_dashboard_display_v1(uuid,date,date,date,date) from public,anon;
grant execute on function public.hub_kpi_dashboard_display_v1(uuid,date,date,date,date) to authenticated;
