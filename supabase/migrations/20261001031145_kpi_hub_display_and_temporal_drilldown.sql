-- Additive display contract. Existing Hub v4 remains the authoritative headline.
alter table public.kpi_project_unit_mappings add column if not exists valid_from date;
alter table public.kpi_project_unit_mappings add column if not exists valid_to date;

create function private.hub_kpi_financial_facts_v1(p_tenant_id uuid,p_from date,p_to date)
returns table(fact_id text,occurred_on date,kind text,amount numeric,category text,project text,vehicle text,unit_id uuid,unit_name text,business_group text,source text,description text,account text,file_name text,row_number integer,original jsonb)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 then raise exception 'Invalid period'; end if;
 return query
 with cfg0 as (
  select coalesce(monthly_salary,34000)::numeric salary,coalesce(weekly_hours,40)::numeric wh,coalesce(overtime_multiplier,1.5)::numeric ot,
   (1+(coalesce(employer_contribution_pct,31.42)+coalesce(pension_pct,4.5)+coalesce(other_overhead_pct,0))/100)::numeric load
  from public.kpi_personnel_salary_settings where tenant_id=p_tenant_id and is_default limit 1
 ), cfg as (select * from cfg0 union all select 34000,40,1.5,1.3592 where not exists(select 1 from cfg0)),
 times as (select t.*,date_trunc('week',work_date)::date wk from public.kpi_transpa_time_facts t where t.tenant_id=p_tenant_id and work_date between p_from and p_to and work_hours>0),
 weeks as (select employee_id,wk,sum(work_hours) hours from times group by 1,2),
 payroll as (
  select t.*,(case when w.hours<=c.wh then t.work_hours else t.work_hours*c.wh/w.hours end +
   case when w.hours<=c.wh then 0 else t.work_hours*(w.hours-c.wh)/w.hours*c.ot end)*c.salary/(c.wh*52/12)*c.load pc
  from times t join weeks w using(employee_id,wk) cross join cfg c
 ), imports as (
  select x.id::text fid,x.occurred_on dt,x.data_kind k,x.amount amt,
   case when x.data_kind='revenue' then coalesce(ar.revenue_category,'unclassified')
    when x.project_reference='9009' then 'hired' when x.project_reference='5100' then 'tipp_deponi'
    when x.account in ('5360','5621','5631') then 'fuel' else coalesce(cr.cost_category,'other') end cat,
   case when x.data_kind='revenue' then case when ar.target_type='project' then nullif(trim(ar.project_reference),'') else null end
    else coalesce(nullif(x.allocation->>'allocation_reference',''),x.project_reference) end proj,
   case when x.data_kind='revenue' and ar.target_type='vehicle' then upper(trim(x.vehicle_registration))
    when x.data_kind='cost' then null else null end reg,
   case when x.data_kind='cost' then 'NEXT' else 'Workify' end src,x.description descr,x.account acc,b.file_name fn,x.row_number rn,x.source_data raw
  from public.kpi_import_rows x join public.kpi_import_batches b on b.id=x.batch_id
  left join lateral (select a.* from public.kpi_workify_article_rules a where a.tenant_id=p_tenant_id and a.enabled and a.article_number=coalesce(x.source_data->>'Artikelnummer','') and x.occurred_on>=a.valid_from and (a.valid_to is null or x.occurred_on<=a.valid_to) order by a.valid_from desc,a.id limit 1) ar on true
  left join lateral (select r.cost_category from public.kpi_cost_category_rules r where r.tenant_id=p_tenant_id and r.account=x.account and x.occurred_on>=r.valid_from and (r.valid_to is null or x.occurred_on<=r.valid_to) order by r.valid_from desc,r.id limit 1) cr on true
  where x.tenant_id=p_tenant_id and x.is_valid and x.data_kind in ('revenue','cost') and x.occurred_on between p_from and p_to
 ), raw_facts as (
  select * from imports
  union all
  select 'transpa:'||t.time_report_id||':'||coalesce(j.ordinality,0),t.work_date,'cost',t.pc/greatest(jsonb_array_length(coalesce(t.transpa_vehicle_ids,'[]')),1),
   'personnel',null,upper(trim(v.payload->>'registrationNumber')),'TransPA',
   'Beräknad personalkostnad från TransPA-tid (Hub-schablon)',null,null,null,
   jsonb_build_object('time_report_id',t.time_report_id,'employee_id',t.employee_id,'work_date',t.work_date,'work_hours',t.work_hours,'report_status',t.report_status,'calculation','hub_kpi_personnel_costs_engine_v1','actual_payroll',false)
  from payroll t left join lateral jsonb_array_elements(t.transpa_vehicle_ids) with ordinality j(value,ordinality) on true
  left join public.hub_transpa_entities v on v.tenant_id=p_tenant_id and v.entity_type='vehicle' and v.external_id=j.value#>>'{}'
  union all
  select 'depreciation:'||d.id||':'||gs::date,greatest(gs::date,p_from,d.valid_from),'cost',d.monthly_depreciation,'depreciation',null,upper(trim(d.object_reference)),'Avskrivningsregister',
   'Månadsavskrivning',null,null,null,jsonb_build_object('register_id',d.id,'valid_from',d.valid_from,'valid_to',d.valid_to,'monthly_depreciation',d.monthly_depreciation)
  from public.kpi_asset_depreciation_periods d cross join lateral generate_series(date_trunc('month',greatest(p_from,d.valid_from)),date_trunc('month',least(p_to,coalesce(d.valid_to,p_to))),interval '1 month') gs
  where d.tenant_id=p_tenant_id and d.valid_from<=p_to and (d.valid_to is null or d.valid_to>=p_from)
 ), mapped as (
  select f.*,case when f.proj='9009' or f.reg='LASTBIL' then 'LASTBIL' else coalesce(nullif(f.reg,''),m.reg) end vrn
  from raw_facts f left join lateral (
   select case when count(distinct upper(trim(vehicle_registration)))=1 then max(upper(trim(vehicle_registration))) end reg
   from public.kpi_project_unit_mappings pm where pm.tenant_id=p_tenant_id and pm.enabled and pm.project_reference=f.proj and f.dt>=coalesce(pm.valid_from,'2000-01-01') and (pm.valid_to is null or f.dt<=pm.valid_to)
  ) m on true
 ), related as (
  select f.*,u.uid,u.uname,
   case when f.proj='9009' or f.vrn='LASTBIL' then 'Inhyrda' else coalesce(bg.name,'Ej klassificerat') end grp
  from mapped f left join lateral (
   select case when count(distinct un.id)=1 then (array_agg(distinct un.id))[1] end uid,
    case when count(distinct un.id)=1 then max(un.name) end uname
   from public.kpi_units un where un.tenant_id=p_tenant_id and un.enabled and un.origin in ('manual','manual_builder') and un.valid_from<=f.dt and (un.valid_to is null or un.valid_to>=f.dt)
   and (f.proj=any(un.projects) or f.vrn=any(un.registrations) or f.raw->>'employee_id'=any(un.employees) or exists(
    select 1 from public.kpi_unit_components c where c.tenant_id=p_tenant_id and c.unit_id=un.id and c.component_type in ('vehicle','trailer','other') and upper(trim(c.component_reference))=f.vrn and coalesce(c.valid_from,un.valid_from)<=f.dt and (c.valid_to is null or f.dt<=c.valid_to)))
  ) u on true
  left join lateral (
   select case when count(distinct p.business_group_id)=1 then (array_agg(distinct p.business_group_id))[1] end gid
   from public.kpi_project_business_groups p where p.tenant_id=p_tenant_id and p.project_reference=f.proj and f.dt>=coalesce(p.valid_from,'2000-01-01') and (p.valid_to is null or f.dt<=p.valid_to)
  ) pg on true left join public.kpi_business_groups bg on bg.id=pg.gid and bg.tenant_id=p_tenant_id and bg.enabled
 ) select f.fid,f.dt,f.k,f.amt,f.cat,f.proj,f.vrn,f.uid,f.uname,f.grp,f.src,f.descr,f.acc,f.fn,f.rn,f.raw from related f;
end $$;
revoke all on function private.hub_kpi_financial_facts_v1(uuid,date,date) from public,anon;
grant execute on function private.hub_kpi_financial_facts_v1(uuid,date,date) to authenticated;

create function public.hub_kpi_analysis_v1(p_tenant_id uuid,p_from date,p_to date,p_filters jsonb default '{}',p_level text default 'group',p_grain text default 'month',p_page integer default 0,p_export boolean default false)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if p_level not in ('group','unit','project','transaction') or p_grain not in ('year','month','week','day') or p_page<0 then raise exception 'Invalid analysis filter';end if;
 with facts as materialized(select * from private.hub_kpi_financial_facts_v1(p_tenant_id,p_from,p_to)), scoped as (
  select f.* from facts f where
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
end $$;
revoke all on function public.hub_kpi_analysis_v1(uuid,date,date,jsonb,text,text,integer,boolean) from public,anon;
grant execute on function public.hub_kpi_analysis_v1(uuid,date,date,jsonb,text,text,integer,boolean) to authenticated;

create function public.hub_kpi_dashboard_display_v1(p_tenant_id uuid,p_from date,p_to date,p_previous_from date default null,p_previous_to date default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare hub jsonb; legacy jsonb; result jsonb; prev jsonb; report jsonb; vehicle_rows jsonb; categories jsonb; derived jsonb; hours numeric; fuel numeric; personnel numeric;
begin
 -- Force access validation before calling existing Hub engines.
 perform 1 from private.hub_kpi_financial_facts_v1(p_tenant_id,p_from,p_to) limit 1;
 hub:=public.hub_kpi_transport_dashboard_v4(p_tenant_id,p_from,p_to);
 legacy:=public.kpi_transport_dashboard(p_tenant_id,p_from,p_to);
 report:=public.hub_kpi_analysis_v1(p_tenant_id,p_from,p_to);
 hours:=coalesce((public.kpi_transport_efficiency(p_tenant_id,p_from,p_to)->>'worked_hours')::numeric,0);
 fuel:=coalesce((select (value->>'amount')::numeric from jsonb_array_elements(hub->'cost_categories') where value->>'category'='fuel'),0);
 personnel:=coalesce((select (value->>'amount')::numeric from jsonb_array_elements(hub->'cost_categories') where value->>'category'='personnel'),0)+(hub#>>'{components,transpa_personnel_cost}')::numeric;
 select jsonb_object_agg(cat,amt) into categories from (
  select value->>'category' cat,(value->>'amount')::numeric amt from jsonb_array_elements(hub->'cost_categories') where value->>'category'<>'personnel'
  union all select 'personnel',personnel union all select 'depreciation',(hub#>>'{components,depreciation_cost}')::numeric
 ) c;
 with f as (select * from private.hub_kpi_financial_facts_v1(p_tenant_id,p_from,p_to)), v as (
  select coalesce(vehicle,'Ej fördelat') vehicle,
   coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost,
   coalesce(sum(amount) filter(where kind='cost' and category='fuel'),0) fuel_cost,
   coalesce(sum(amount) filter(where source='TransPA'),0) personnel_cost,
   coalesce(sum(case when kind='revenue' then amount else -amount end),0) result
  from f group by vehicle
 ), t as (select value x from jsonb_array_elements(coalesce(public.kpi_transpa_vehicle_time(p_tenant_id,p_from,p_to)->'vehicles','[]')))
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
  'cost_efficiency',jsonb_build_object('worked_hours',hours,'total_cost_per_hour',case when hours>0 then round((hub#>>'{metrics,total_cost}')::numeric/hours,2) end,'personnel_cost_per_hour',case when hours>0 then round(personnel/hours,2) end,'fuel_cost_per_hour',case when hours>0 then round(fuel/hours,2) end,'result_per_hour',case when hours>0 then round((hub#>>'{metrics,result}')::numeric/hours,2) end),
  'reconciliation',jsonb_build_object('source_revenue',hub#>'{metrics,revenue}','source_next_cost',hub#>'{components,next_total_cost}','detail_revenue',report#>'{summary,revenue}','detail_next_cost',report#>'{summary,next_cost}',
  'matches',hub#>'{metrics,revenue}'=report#>'{summary,revenue}' and hub#>'{components,next_total_cost}'=report#>'{summary,next_cost}'),
  'personnel_basis','TransPA-tid × Hub-schablon; inte verifierad löneexport');
 return result;
end $$;
revoke all on function public.hub_kpi_dashboard_display_v1(uuid,date,date,date,date) from public,anon;
grant execute on function public.hub_kpi_dashboard_display_v1(uuid,date,date,date,date) to authenticated;
