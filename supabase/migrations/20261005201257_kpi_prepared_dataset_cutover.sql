CREATE OR REPLACE FUNCTION private.hub_kpi_prepared_overview_v1(p_tenant_id uuid, p_fiscal_year integer, p_selected_months integer[], p_cost_center text DEFAULT NULL::text, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
AS $function$
declare current_data jsonb; previous_data jsonb; filters jsonb; months integer[]; options jsonb; unclassified jsonb; previous_filters jsonb; comparison_available boolean;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501'; end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);
 select coalesce(jsonb_agg(jsonb_build_object('code',code,'name',name) order by code),'[]') into options from (select cost_center code,min(cost_center_name) name from (select id,tenant_id,project_reference,project_name,cost_center,cost_center_name,business_group,registrations,valid_from,valid_to,source,created_at from private.hub_kpi_prepared_kpi_project_classification_periods where generation_id=private.hub_kpi_active_report_generation_v1(p_tenant_id)) where tenant_id=p_tenant_id group by cost_center union all select 'unclassified','Ej klassificerat') x;
 if p_cost_center is not null and exists(select 1 from unnest(string_to_array(p_cost_center,',')) requested(code) where not exists(select 1 from jsonb_array_elements(options) o where o->>'code'=requested.code)) then raise exception 'Okänt kostnadsställe'; end if;
 filters:=p_filters-'fiscal_year'-'selected_months'-'cost_center';
 if p_cost_center is not null then filters:=filters||jsonb_build_object('cost_center',p_cost_center);end if;
 current_data:=private.hub_kpi_prepared_snapshot_v1(p_tenant_id,p_fiscal_year,months,filters);
 previous_filters:=filters;
 if filters?'date_from' then previous_filters:=jsonb_set(previous_filters,'{date_from}',to_jsonb(((filters->>'date_from')::date-interval '1 year')::date));end if;
 if filters?'date_to' then previous_filters:=jsonb_set(previous_filters,'{date_to}',to_jsonb(((filters->>'date_to')::date-interval '1 year')::date));end if;
 previous_data:=private.hub_kpi_prepared_snapshot_v1(p_tenant_id,p_fiscal_year-1,months,previous_filters);
 comparison_available:=jsonb_array_length(previous_data#>'{coverage,revenue_months}')=cardinality(months) and jsonb_array_length(previous_data#>'{coverage,cost_months}')=cardinality(months) and jsonb_array_length(current_data#>'{coverage,revenue_months}')=cardinality(months) and jsonb_array_length(current_data#>'{coverage,cost_months}')=cardinality(months);

 return current_data||jsonb_build_object('sync',private.hub_kpi_report_status_v1(p_tenant_id),'previous',previous_data,'comparison_available',comparison_available,'cost_centers',options,'cost_center_scope',p_cost_center,'classification_valid_from',(select min(valid_from) from (select id,tenant_id,project_reference,project_name,cost_center,cost_center_name,business_group,registrations,valid_from,valid_to,source,created_at from private.hub_kpi_prepared_kpi_project_classification_periods where generation_id=private.hub_kpi_active_report_generation_v1(p_tenant_id)) where tenant_id=p_tenant_id),'metrics',current_data->'metrics'||jsonb_build_object('revenue_change_pct',case when comparison_available then round(((current_data#>>'{metrics,revenue}')::numeric/(nullif((previous_data#>>'{metrics,revenue}')::numeric,0))-1)*100,2) else null end));
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_overview_months_v1(p_tenant_id uuid,p_fiscal_year integer,p_selected_months integer[],p_cost_center text default null,p_filters jsonb default '{}')
returns jsonb language sql stable set search_path='' set statement_timeout='30s'
as $fn$ select private.hub_kpi_prepared_overview_v1(p_tenant_id,p_fiscal_year,p_selected_months,p_cost_center,p_filters); $fn$;

CREATE OR REPLACE FUNCTION private.hub_kpi_month_facts_v1(p_tenant_id uuid, p_year integer, p_months integer[], p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb, cost_center text, cost_center_name text, classification_source jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare generation uuid;
begin
 generation:=private.hub_kpi_active_report_generation_v1(p_tenant_id);
 if not exists(select 1 from private.hub_kpi_report_generations g where g.id=generation and p_year between g.first_fiscal_year and g.last_fiscal_year) then raise exception 'Fiscal year outside prepared report coverage' using errcode='55000';end if;
 perform private.hub_kpi_month_scope_v1(p_year,p_months);
 return query select f.fact_id,f.occurred_on,f.kind,f.amount,f.category,f.project,f.vehicle,f.unit_id,f.unit_name,f.business_group,f.source,f.description,f.account,f.file_name,f.row_number,case when coalesce((p_filters->>'_display_projection')::boolean,false) then f.display_original else f.original end,f.cost_center,f.cost_center_name,case when coalesce((p_filters->>'_display_projection')::boolean,false) then '{}'::jsonb else f.classification_source end from private.hub_kpi_prepared_facts f
 where f.generation_id=generation and f.tenant_id=p_tenant_id and f.fiscal_year=p_year and extract(month from f.occurred_on)::int=any(p_months)
 and (not(p_filters?'cost_center') or f.cost_center=any(string_to_array(p_filters->>'cost_center',',')))
 and (not(p_filters?'group') or f.business_group=any(string_to_array(p_filters->>'group',',')))
 and (not(p_filters?'unit') or coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=p_filters->>'unit')
 and (not(p_filters?'vehicle') or coalesce(f.vehicle,'unassigned')=p_filters->>'vehicle')
 and (not(p_filters?'project') or coalesce(f.project,'unassigned')=p_filters->>'project')
 and (not(p_filters?'category') or f.category=p_filters->>'category')
 and (not(p_filters?'kind') or f.kind=p_filters->>'kind')
 and (not(p_filters?'source') or f.source=p_filters->>'source')
 and (not(p_filters?'date_from') or f.occurred_on>=(p_filters->>'date_from')::date)
 and (not(p_filters?'date_to') or f.occurred_on<=(p_filters->>'date_to')::date);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_analysis_v2(p_tenant_id uuid, p_from date, p_to date, p_filters jsonb DEFAULT '{}'::jsonb, p_level text DEFAULT 'group'::text, p_grain text DEFAULT 'month'::text, p_page integer DEFAULT 0, p_export boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 if p_level not in ('group','unit','project','transaction') or p_grain not in ('year','month','week','day') or p_page<0 then raise exception 'Invalid analysis filter';end if;
 with facts as materialized(select * from private.hub_kpi_prepared_range_facts_v1(p_tenant_id,p_from,p_to)), scoped as (
  select f.* from facts f where
   (not(p_filters?'cost_center') or f.cost_center=any(string_to_array(p_filters->>'cost_center',','))) and
   (not(p_filters?'group') or f.business_group=any(string_to_array(p_filters->>'group',','))) and
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
CREATE OR REPLACE FUNCTION public.hub_kpi_cost_center_dashboard_v1(p_tenant_id uuid, p_from date, p_to date, p_cost_center text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare weekly jsonb; base jsonb; previous jsonb; details jsonb; options jsonb; filters jsonb; rev numeric; prev_rev numeric; fiscal_year integer; end_fiscal_year integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI-behörighet saknas' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_to<p_from then raise exception 'Ogiltig period'; end if;
 fiscal_year:=extract(year from p_from)::integer-case when extract(month from p_from)<9 then 1 else 0 end;
 end_fiscal_year:=extract(year from p_to)::integer-case when extract(month from p_to)<9 then 1 else 0 end;
 if fiscal_year=end_fiscal_year then
 return private.hub_kpi_prepared_overview_v1(p_tenant_id,fiscal_year,array[9,10,11,12,1,2,3,4,5,6,7,8],p_cost_center,jsonb_build_object('date_from',p_from,'date_to',p_to));
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('code',code,'name',name) order by code),'[]') into options from(select cost_center code,min(cost_center_name) name from public.kpi_project_classification_periods where tenant_id=p_tenant_id group by cost_center union all select 'unclassified','Ej klassificerat') x;
 if p_cost_center is not null and exists(select 1 from unnest(string_to_array(p_cost_center,',')) requested(code) where not exists(select 1 from jsonb_array_elements(options) o where o->>'code'=requested.code)) then raise exception 'Okänt kostnadsställe'; end if;
 filters:=case when p_cost_center is null then '{}'::jsonb else jsonb_build_object('cost_center',p_cost_center) end;
 details:=public.hub_kpi_analysis_v2(p_tenant_id,p_from,p_to,filters,'group','month',0,false);
 if p_cost_center is null then
  base:=public.hub_kpi_dashboard_display_v1(p_tenant_id,p_from,p_to);
  base:=base||jsonb_build_object('business_groups',details->'groups');
 else
  base:=private.hub_kpi_cost_center_finance_v1(p_tenant_id,p_from,p_to,p_cost_center);
  if exists(select 1 from public.kpi_project_classification_periods where tenant_id=p_tenant_id and cost_center=any(string_to_array(p_cost_center,',')) and valid_from<=(p_from-interval '1 year')::date and (valid_to is null or valid_to>=(p_to-interval '1 year')::date)) then
   previous:=private.hub_kpi_cost_center_finance_v1(p_tenant_id,(p_from-interval '1 year')::date,(p_to-interval '1 year')::date,p_cost_center);
  end if;
  rev:=(base->'metrics'->>'revenue')::numeric;prev_rev:=(previous->'metrics'->>'revenue')::numeric;
  base:=jsonb_set(base,'{metrics,revenue_change_pct}',coalesce(to_jsonb(round((rev-prev_rev)/nullif(prev_rev,0)*100,2)),'null'::jsonb));
  weekly:=public.hub_kpi_analysis_v2(p_tenant_id,p_from,p_to,filters,'group','week',0,false);
  base:=base||jsonb_build_object('weekly',jsonb_build_object('weeks',(select coalesce(jsonb_agg(jsonb_build_object('week_start',w->>'period_start','revenue',w->'revenue','previous_revenue',null)),'[]') from jsonb_array_elements(weekly->'periods') w)));
  base:=base||jsonb_build_object('previous',previous,'personnel_basis','TransPA-tid × Hub-schablon; inte verifierad löneexport','cost_efficiency','{}'::jsonb,'efficiency',null,'transpa_vehicle_time',null,'hired_capacity',null,'driver_productivity',null,'scoped_operational_unavailable',true,'repair_summary',null);
 end if;
 return base||jsonb_build_object('unclassified_summary',public.hub_kpi_analysis_v2(p_tenant_id,p_from,p_to,'{"cost_center":"unclassified"}'::jsonb,'group','month',0,false)->'summary','cost_centers',options,'cost_center_scope',p_cost_center,'classification_valid_from',(select min(valid_from) from public.kpi_project_classification_periods where tenant_id=p_tenant_id),'reconciliation',jsonb_build_object('matches',(base->'metrics'->>'revenue')::numeric=(details->'summary'->>'revenue')::numeric and (base->'metrics'->>'total_cost')::numeric=(details->'summary'->>'cost')::numeric,'source','Hub authoritative facts, dated classification','details',details->'summary'));
end $function$;

revoke all on function private.hub_kpi_prepared_overview_v1(uuid,integer,integer[],text,jsonb) from public,anon;
grant execute on function private.hub_kpi_prepared_overview_v1(uuid,integer,integer[],text,jsonb) to authenticated;
grant execute on function private.hub_kpi_prepared_range_facts_v1(uuid,date,date) to authenticated;
revoke all on function private.hub_kpi_month_facts_v1(uuid,integer,integer[],jsonb) from public,anon;
grant execute on function private.hub_kpi_month_facts_v1(uuid,integer,integer[],jsonb) to authenticated;
notify pgrst,'reload schema';
