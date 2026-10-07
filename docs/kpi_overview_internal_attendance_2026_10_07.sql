CREATE OR REPLACE FUNCTION private.hub_kpi_internal_overview_v1(p_tenant_id uuid,p_fiscal_year integer,p_months integer[],p_filters jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path='' AS $function$
declare base jsonb; result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 base:=public.hub_kpi_internal_transfers_v1(p_tenant_id,make_date(p_fiscal_year,9,1),make_date(p_fiscal_year+1,8,31),p_months);
 with linked as (
 select r,coalesce((r->>'ready')::boolean,false) and r->>'status'<>'changed' and r->>'category' in ('transport','material','tipp_deponi') and (r->>'category'<>'tipp_deponi' or r->>'carrier_type'='project') ready
 from jsonb_array_elements(base->'rows')r
 where (not(p_filters?'cost_center') or r->>'source_center'=any(string_to_array(p_filters->>'cost_center',',')))
 and (not(p_filters?'vehicle') or case when r->>'vehicle'='Inhyrda lastbilar' then 'LASTBIL' else r->>'vehicle' end=p_filters->>'vehicle')
 and (not(p_filters?'project') or r->>'project'=p_filters->>'project' or r->>'carrier_reference'=p_filters->>'project')
 and (not(p_filters?'kind') or p_filters->>'kind'='revenue')
 and (not(p_filters?'source') or p_filters->>'source'='Workify')
 and (not(p_filters?'category') or r->>'category'=p_filters->>'category')
 and (not(p_filters?'date_from') or (r->>'occurred_on')::date>=(p_filters->>'date_from')::date)
 and (not(p_filters?'date_to') or (r->>'occurred_on')::date<=(p_filters->>'date_to')::date)
 and (not(p_filters?'group') or exists(select 1 from public.kpi_project_classification_periods c where c.tenant_id=p_tenant_id and c.valid_from<=(r->>'occurred_on')::date and (c.valid_to is null or c.valid_to>=(r->>'occurred_on')::date) and c.business_group=any(string_to_array(p_filters->>'group',',')) and ((r->>'carrier_type'='project' and c.project_reference=r->>'carrier_reference') or (r->>'carrier_type'='vehicle' and ((r->>'vehicle')=any(c.registrations) or (r->>'vehicle'='Inhyrda lastbilar' and c.project_reference='9009'))))))
 and (not(p_filters?'unit') or p_filters->>'unit'='vehicle:'||case when r->>'vehicle'='Inhyrda lastbilar' then 'LASTBIL' else r->>'vehicle' end
 or exists(select 1 from public.kpi_unit_periods v join public.kpi_units u on u.id=v.unit_id and u.tenant_id=v.tenant_id where v.tenant_id=p_tenant_id and u.id::text=p_filters->>'unit' and v.valid_from<=(r->>'occurred_on')::date and (v.valid_to is null or v.valid_to>=(r->>'occurred_on')::date) and coalesce((v.payload->>'enabled')::boolean,u.enabled) and ((v.payload->'registrations') ? (r->>'vehicle') or (r->>'carrier_type'='project' and (v.payload->'projects') ? (r->>'carrier_reference')))))
 )
 select jsonb_build_object('total',round(coalesce(sum((r->>'amount')::numeric) filter(where ready),0),2),
 'material',round(coalesce(sum((r->>'amount')::numeric) filter(where ready and r->>'category'='material'),0),2),
 'tipp_deponi',round(coalesce(sum((r->>'amount')::numeric) filter(where ready and r->>'category'='tipp_deponi'),0),2),
 'transport',round(coalesce(sum((r->>'amount')::numeric) filter(where ready and r->>'category'='transport'),0),2),
 'rows',count(*)filter(where ready),'review_rows',count(*)filter(where not ready),
 'review_amount',round(coalesce(sum((r->>'amount')::numeric)filter(where not ready),0),2),
 'basis','Fakturerade och kopplade Workify-rader med kund Elleholms Maskin AB. Kostnadsställe avser utförande sida. Separat från extern omsättning.') into result from linked;
 return result;
end $function$;
REVOKE ALL ON FUNCTION private.hub_kpi_internal_overview_v1(uuid,integer,integer[],jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.hub_kpi_prepared_overview_v1(p_tenant_id uuid, p_fiscal_year integer, p_selected_months integer[], p_cost_center text DEFAULT NULL::text, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
AS $function$
declare internal_data jsonb; current_data jsonb; previous_data jsonb; filters jsonb; months integer[]; options jsonb; unclassified jsonb; previous_filters jsonb; comparison_available boolean;
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
 previous_data:=private.hub_kpi_prepared_comparison_v1(p_tenant_id,p_fiscal_year-1,months,previous_filters);
 comparison_available:=jsonb_array_length(previous_data#>'{coverage,revenue_months}')=cardinality(months) and jsonb_array_length(previous_data#>'{coverage,cost_months}')=cardinality(months) and jsonb_array_length(current_data#>'{coverage,revenue_months}')=cardinality(months) and jsonb_array_length(current_data#>'{coverage,cost_months}')=cardinality(months);

 internal_data:=private.hub_kpi_internal_overview_v1(p_tenant_id,p_fiscal_year,months,filters);
 internal_data:=internal_data||jsonb_build_object('revenue_basis',(current_data#>>'{metrics,revenue}')::numeric,
 'total_percent',round((internal_data->>'total')::numeric/nullif((current_data#>>'{metrics,revenue}')::numeric,0)*100,2),
 'material_percent',round((internal_data->>'material')::numeric/nullif((current_data#>>'{metrics,revenue}')::numeric,0)*100,2),
 'tipp_deponi_percent',round((internal_data->>'tipp_deponi')::numeric/nullif((current_data#>>'{metrics,revenue}')::numeric,0)*100,2));
 return current_data||jsonb_build_object('internal_summary',internal_data,'driver_attendance',jsonb_build_object('status','missing_absence_data','attendance_percent',null,'sick_percent',null,'vab_percent',null,'vacation_percent',null,'other_absence_percent',null,'basis','TransPA-kopplingen har arbetad tid men saknar frånvaroaktiviteter och verifierad schematid. Frånvaroprocent kan inte beräknas.'),'sync',private.hub_kpi_report_status_v1(p_tenant_id),'previous',previous_data,'comparison_available',comparison_available,'cost_centers',options,'cost_center_scope',p_cost_center,'classification_valid_from',(select min(valid_from) from (select id,tenant_id,project_reference,project_name,cost_center,cost_center_name,business_group,registrations,valid_from,valid_to,source,created_at from private.hub_kpi_prepared_kpi_project_classification_periods where generation_id=private.hub_kpi_active_report_generation_v1(p_tenant_id)) where tenant_id=p_tenant_id),'metrics',current_data->'metrics'||jsonb_build_object('revenue_change_pct',case when comparison_available then round(((current_data#>>'{metrics,revenue}')::numeric/(nullif((previous_data#>>'{metrics,revenue}')::numeric,0))-1)*100,2) else null end));
end $function$
