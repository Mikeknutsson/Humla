-- Isolated KPI period contract. Does not mutate sync, identities or source data.
create function private.hub_kpi_month_scope_v1(p_year integer,p_months integer[]) returns integer[]
language plpgsql immutable set search_path='' as $$
declare months integer[];
begin
 if p_year is null or p_year<2000 or p_year>2100 or p_months is null or cardinality(p_months)=0
 or exists(select 1 from unnest(p_months) m where m is null or m<1 or m>12) then
 raise exception 'Välj verksamhetsår och minst en giltig månad' using errcode='22023'; end if;
 select array_agg(m order by (m+3)%12) into months from(select distinct unnest(p_months) m) x;
 return months;
end $$;
revoke all on function private.hub_kpi_month_scope_v1(integer,integer[]) from public,anon;
grant execute on function private.hub_kpi_month_scope_v1(integer,integer[]) to authenticated;

create function private.hub_kpi_month_facts_v1(p_tenant_id uuid,p_year integer,p_months integer[],p_filters jsonb default '{}')
returns TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb, cost_center text, cost_center_name text, classification_source jsonb) language plpgsql stable security invoker set search_path='' as $$
begin
 perform private.hub_kpi_month_scope_v1(p_year,p_months);
 return query select f.* from private.hub_kpi_classified_facts_v1(p_tenant_id,make_date(p_year,9,1),make_date(p_year+1,8,31)) f
 where extract(month from f.occurred_on)::int=any(p_months)
 and (not(p_filters?'cost_center') or f.cost_center=p_filters->>'cost_center')
 and (not(p_filters?'group') or f.business_group=p_filters->>'group')
 and (not(p_filters?'unit') or coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=p_filters->>'unit')
 and (not(p_filters?'vehicle') or f.vehicle=p_filters->>'vehicle')
 and (not(p_filters?'project') or coalesce(f.project,'unassigned')=p_filters->>'project')
 and (not(p_filters?'category') or f.category=p_filters->>'category')
 and (not(p_filters?'kind') or f.kind=p_filters->>'kind')
 and (not(p_filters?'source') or f.source=p_filters->>'source')
 and (not(p_filters?'date_from') or f.occurred_on>=(p_filters->>'date_from')::date)
 and (not(p_filters?'date_to') or f.occurred_on<=(p_filters->>'date_to')::date);
end $$;
revoke all on function private.hub_kpi_month_facts_v1(uuid,integer,integer[],jsonb) from public,anon;
grant execute on function private.hub_kpi_month_facts_v1(uuid,integer,integer[],jsonb) to authenticated;

CREATE OR REPLACE FUNCTION public.hub_kpi_analysis_months_v1(p_tenant_id uuid, p_from date, p_to date, p_filters jsonb DEFAULT '{}'::jsonb, p_level text DEFAULT 'group'::text, p_grain text DEFAULT 'month'::text, p_page integer DEFAULT 0, p_export boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare result jsonb; fiscal_year integer; months integer[];
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501'; end if;
 fiscal_year:=(p_filters->>'fiscal_year')::int;
 select array_agg(value::int) into months from jsonb_array_elements_text(p_filters->'selected_months');
 months:=private.hub_kpi_month_scope_v1(fiscal_year,months);
 if p_level not in ('group','unit','project','transaction') or p_grain not in ('year','month','week','day') or p_page<0 then raise exception 'Invalid analysis filter';end if;
 with facts as materialized(select * from private.hub_kpi_month_facts_v1(p_tenant_id,fiscal_year,months,p_filters)), scoped as (
  select f.* from facts f where
   (not(p_filters?'cost_center') or f.cost_center=p_filters->>'cost_center') and
   (not(p_filters?'group') or f.business_group=p_filters->>'group') and
   (not(p_filters?'unit') or coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=p_filters->>'unit') and
   (not(p_filters?'vehicle') or f.vehicle=p_filters->>'vehicle') and
   (not(p_filters?'project') or coalesce(f.project,'unassigned')=p_filters->>'project') and
   (not(p_filters?'category') or f.category=p_filters->>'category') and
   (not(p_filters?'kind') or f.kind=p_filters->>'kind') and
   (not(p_filters?'source') or f.source=p_filters->>'source') and
   (not(p_filters?'date_from') or f.occurred_on>=(p_filters->>'date_from')::date) and
   (not(p_filters?'date_to') or f.occurred_on<=(p_filters->>'date_to')::date)
 ), summary as (
  select round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,
   round(coalesce(sum(amount) filter(where source='NEXT'),0),2) next_cost,round(coalesce(sum(amount) filter(where source='TransPA'),0),2) personnel_cost,count(*) rows from scoped
 ), keyed as (
  select *,case p_level when 'group' then business_group when 'unit' then coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') when 'project' then coalesce(project,'unassigned') else fact_id end group_key,
   case p_level when 'group' then business_group when 'unit' then coalesce(unit_name,vehicle,'Ej fördelat') when 'project' then coalesce(project,'Ej projektfördelat') else coalesce(description,fact_id) end group_label
  from scoped
 ), groups as (
  select group_key key,max(group_label) label,count(*) rows,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,
   round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,
   round(coalesce(sum(case when kind='revenue' then amount else -amount end),0),2) result from keyed group by group_key
 ), periods as (
  select case p_grain when 'year' then make_date(extract(year from occurred_on)::int-case when extract(month from occurred_on)<9 then 1 else 0 end,9,1) else date_trunc(p_grain,occurred_on)::date end period_start,
   round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,
   round(coalesce(sum(case when kind='revenue' then amount else -amount end),0),2) result,count(*) rows from scoped group by 1
 ), page_rows as (select * from scoped order by occurred_on desc,fact_id limit case when p_export then 50001 else 100 end offset case when p_export then 0 else p_page*100 end)
 select jsonb_build_object('period',jsonb_build_object('from',p_from,'to',p_to),'filters',p_filters,'level',p_level,'grain',p_grain,'page',p_page,
  'summary',(select to_jsonb(s)||jsonb_build_object('result',revenue-cost,'margin_pct',case when revenue<>0 then round((revenue-cost)/revenue*100,2) else null end) from summary s),
  'groups',coalesce((select jsonb_agg(to_jsonb(g) order by g.label) from groups g),'[]'),
  'periods',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('period_end',least(p_to,coalesce((p_filters->>'date_to')::date,p_to),case p_grain when 'year' then (period_start+interval '1 year'-interval '1 day')::date when 'month' then (period_start+interval '1 month'-interval '1 day')::date when 'week' then period_start+6 else period_start end),'period_start',greatest(p_from,coalesce((p_filters->>'date_from')::date,p_from),period_start)) order by period_start) from periods p),'[]'),
  'transactions',coalesce((select jsonb_agg(to_jsonb(r)) from page_rows r),'[]'),
  'page_size',100,'export_limit_exceeded',(select count(*)>50000 from scoped)
 ) into result;
 return result;
end $function$;


revoke all on function public.hub_kpi_analysis_months_v1(uuid,date,date,jsonb,text,text,integer,boolean) from public,anon;
grant execute on function public.hub_kpi_analysis_months_v1(uuid,date,date,jsonb,text,text,integer,boolean) to authenticated;

create or replace function private.hub_kpi_month_snapshot_v1(p_tenant_id uuid,p_fiscal_year integer,p_selected_months integer[],p_filters jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare output jsonb; months integer[]; fy_from date; fy_to date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501'; end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);
 fy_from:=make_date(p_fiscal_year,9,1);fy_to:=make_date(p_fiscal_year+1,8,31);
 with selected_facts as materialized(select * from private.hub_kpi_month_facts_v1(p_tenant_id,p_fiscal_year,months,p_filters-'cost_center')),
 facts as materialized(select * from selected_facts where not(p_filters?'cost_center') or cost_center=p_filters->>'cost_center'),
 month_dates as(select m,make_date(case when m>=9 then p_fiscal_year else p_fiscal_year+1 end,m,1) dt from unnest(months) m),
 monthly as(select m,dt,coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost,count(f.fact_id) rows from month_dates left join facts f on date_trunc('month',f.occurred_on)::date=dt group by m,dt),
 cats as(select category,round(sum(amount),2) amount from facts where kind='cost' group by category),
 totals as(select coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost,
 coalesce(sum(amount) filter(where kind='revenue' and vehicle='LASTBIL'),0) hired,
 count(distinct vehicle) filter(where kind='revenue' and amount<>0 and vehicle not in ('LASTBIL','Ej fördelat')) vehicles from facts),
 groups as(select business_group key,business_group label,count(*) rows,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by business_group),
 units as(select coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') key,max(coalesce(unit_name,vehicle,'Ej fördelat')) label,count(*) rows,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by 1),
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
 vehicles as(select f.vehicle,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result,round(coalesce(sum(amount) filter(where category='fuel' and kind='cost'),0),2) fuel_cost,round(coalesce(sum(amount) filter(where source='TransPA'),0),2) personnel_cost from facts f where f.vehicle is not null group by f.vehicle)
 select jsonb_build_object(
 'hub_contract_version','fiscal-months-v1','period',jsonb_build_object('fiscal_year',p_fiscal_year,'selected_months',months,'from',fy_from,'to',fy_to),'filters',p_filters,
 'metrics',jsonb_build_object('revenue',round(t.revenue,2),'total_cost',round(t.cost,2),'result',round(t.revenue-t.cost,2),'margin_pct',round((t.revenue-t.cost)/nullif(t.revenue,0)*100,2),'revenue_per_vehicle',round(t.revenue/nullif(t.vehicles,0),2),'diesel_share',round(coalesce((select amount from cats where category='fuel'),0)/nullif(t.revenue,0)*100,2),'vehicle_utilization',round(tt.hours/nullif(tt.available,0)*100,1)),
 'components',(select jsonb_build_object('next_total_cost',round(coalesce(sum(amount) filter(where source='NEXT'),0),2),'transpa_personnel_cost',round(coalesce(sum(amount) filter(where source='TransPA'),0),2),'depreciation_cost',round(coalesce(sum(amount) filter(where kind='cost' and category='depreciation'),0),2)) from facts),
 'monthly',(select jsonb_agg(jsonb_build_object('month',m,'period_start',dt,'period_end',(dt+interval '1 month'-interval '1 day')::date,'revenue',round(revenue,2),'cost',round(cost,2),'result',round(revenue-cost,2),'rows',rows) order by dt) from monthly),
 'business_groups',coalesce((select jsonb_agg(to_jsonb(g) order by label) from groups g),'[]'),
 'economic_units',coalesce((select jsonb_agg(to_jsonb(u) order by label) from units u),'[]'),
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
 'reconciliation',jsonb_build_object('matches',t.revenue=(select sum(revenue) from monthly) and t.cost=(select sum(cost) from monthly),'source','Hub authoritative classified facts, exact selected months')
 ) into output from totals t cross join time_totals tt cross join worked w cross join driver_totals d;
 return output;
end $$;
revoke all on function private.hub_kpi_month_snapshot_v1(uuid,integer,integer[],jsonb) from public,anon;
grant execute on function private.hub_kpi_month_snapshot_v1(uuid,integer,integer[],jsonb) to authenticated;

create or replace function public.hub_kpi_overview_months_v1(p_tenant_id uuid,p_fiscal_year integer,p_selected_months integer[],p_cost_center text default null,p_filters jsonb default '{}')
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare current_data jsonb; previous_data jsonb; filters jsonb; months integer[]; options jsonb; unclassified jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501'; end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);
 select coalesce(jsonb_agg(jsonb_build_object('code',code,'name',name) order by code),'[]') into options from (select cost_center code,min(cost_center_name) name from public.kpi_project_classification_periods where tenant_id=p_tenant_id group by cost_center union all select 'unclassified','Ej klassificerat') x;
 if p_cost_center is not null and not exists(select 1 from jsonb_array_elements(options) o where o->>'code'=p_cost_center) then raise exception 'Okänt kostnadsställe'; end if;
 filters:=p_filters-'fiscal_year'-'selected_months'-'cost_center';
 if p_cost_center is not null then filters:=filters||jsonb_build_object('cost_center',p_cost_center);end if;
 current_data:=private.hub_kpi_month_snapshot_v1(p_tenant_id,p_fiscal_year,months,filters);
 previous_data:=private.hub_kpi_month_snapshot_v1(p_tenant_id,p_fiscal_year-1,months,filters);

 return current_data||jsonb_build_object('previous',previous_data,'cost_centers',options,'cost_center_scope',p_cost_center,'classification_valid_from',(select min(valid_from) from public.kpi_project_classification_periods where tenant_id=p_tenant_id),'metrics',current_data->'metrics'||jsonb_build_object('revenue_change_pct',round(((current_data#>>'{metrics,revenue}')::numeric/(nullif((previous_data#>>'{metrics,revenue}')::numeric,0))-1)*100,2)));
end $$;
revoke all on function public.hub_kpi_overview_months_v1(uuid,integer,integer[],text,jsonb) from public,anon;
grant execute on function public.hub_kpi_overview_months_v1(uuid,integer,integer[],text,jsonb) to authenticated;
-- A single bounded fiscal-year report includes current and prior-year financials.
-- PostgREST hoists this timeout for these RPCs only; role/global limits stay intact.
alter function public.hub_kpi_overview_months_v1(uuid,integer,integer[],text,jsonb) set statement_timeout='30s';
alter function public.hub_kpi_analysis_months_v1(uuid,date,date,jsonb,text,text,integer,boolean) set statement_timeout='30s';
notify pgrst,'reload schema';
