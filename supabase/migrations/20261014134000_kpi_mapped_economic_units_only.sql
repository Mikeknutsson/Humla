-- Filter presentation only; never filter financial facts or recompute totals.
create or replace function private.hub_kpi_mapped_units_projection_v1(p_tenant uuid,p_report jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb:=p_report; mapped jsonb; hidden jsonb; section text;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if jsonb_typeof(result->'economic_units')='array' then
  select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where o.id is not null),'[]'::jsonb),
   jsonb_build_object('count',count(*) filter(where o.id is null),
    'revenue',coalesce(sum((e.value->>'revenue')::numeric) filter(where o.id is null),0),
    'cost',coalesce(sum((e.value->>'cost')::numeric) filter(where o.id is null),0))
  into mapped,hidden
  from jsonb_array_elements(result->'economic_units') with ordinality e(value,ordinality)
  left join public.hub_objects o on o.tenant_id=p_tenant and o.object_type='EconomicUnit' and o.id::text=e.value->>'key';
  result:=result||jsonb_build_object('economic_units',mapped,'economic_unit_scope','mapped','unmapped_economic_units',hidden);
 end if;
 foreach section in array array['month','ytd','previous'] loop
  if jsonb_typeof(result->section)='object' then
   result:=jsonb_set(result,array[section],private.hub_kpi_mapped_units_projection_v1(p_tenant,result->section));
  end if;
 end loop;
 return result;
end $$;
revoke all on function private.hub_kpi_mapped_units_projection_v1(uuid,jsonb) from public,anon;
grant execute on function private.hub_kpi_mapped_units_projection_v1(uuid,jsonb) to authenticated,service_role;

CREATE OR REPLACE FUNCTION public.hub_kpi_overview_months_v1(p_tenant_id uuid, p_fiscal_year integer, p_selected_months integer[], p_cost_center text DEFAULT NULL::text, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
 SET statement_timeout TO '30s'
AS $function$ select private.hub_kpi_mapped_units_projection_v1(p_tenant_id,private.hub_kpi_prepared_overview_v1(p_tenant_id,p_fiscal_year,p_selected_months,p_cost_center,p_filters)); $function$
;
CREATE OR REPLACE FUNCTION public.hub_kpi_monthly_transport_report_v1(p_tenant_id uuid, p_fiscal_year integer, p_month integer, p_cost_center text DEFAULT '30'::text, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare generation uuid;revision integer;report jsonb;center text:=coalesce(nullif(trim(p_cost_center),''),'');
 date_from date;date_to date;control numeric;workify numeric;control_ref text;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')then raise exception 'KPI access required'using errcode='42501';end if;
 perform private.hub_kpi_month_scope_v1(p_fiscal_year,array[p_month]);
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>2000 or exists(select 1 from jsonb_object_keys(p_filters)k where k not in('group','unit','vehicle','project'))then raise exception 'Unsupported monthly report filter';end if;
 if length(center)>100 then raise exception 'Invalid cost center';end if;
 select active_generation,correction_revision into generation,revision from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then raise exception 'Prepared report required';end if;
 select c.report into report from private.hub_kpi_monthly_report_cache c where c.tenant_id=p_tenant_id and c.generation_id=generation and c.correction_revision=revision and c.fiscal_year=p_fiscal_year and c.month=p_month and c.cost_center=center and c.filters=p_filters;
 if found then return private.hub_kpi_mapped_units_projection_v1(p_tenant_id,report);end if;
 if not pg_try_advisory_xact_lock(hashtextextended(concat_ws(':','monthly-report',p_tenant_id,generation,revision,p_fiscal_year,p_month,center,p_filters::text),0))then raise exception 'Månadsrapporten förbereds redan. Försök igen om en stund.'using errcode='55P03';end if;
 report:=private.hub_kpi_monthly_transport_report_base_v1(p_tenant_id,p_fiscal_year,p_month,nullif(center,''),p_filters);
 date_from:=(report#>>'{period,from}')::date;date_to:=(report#>>'{period,to}')::date;
 if p_filters='{}'::jsonb then
  select amount,reference into control,control_ref from private.hub_workify_period_controls where tenant_id=p_tenant_id and period_from=date_from and period_to=date_to and cost_center=center and currency='SEK' limit 1;
  if control is not null then
   select coalesce(sum(amount),0)into workify from private.hub_kpi_prepared_facts where tenant_id=p_tenant_id and generation_id=generation and fiscal_year=p_fiscal_year and occurred_on between date_from and date_to and cost_center=center and source='Workify' and kind='revenue';
   report:=report||jsonb_build_object('reconciliation',jsonb_build_object('status',case when abs(workify-control)>0.005 then 'needs_review' else 'matches_control' end,'workify_in_kpi',workify,'reported_workify',control,'difference',workify-control,'reference',control_ref,'basis','Uppgivet Workify-belopp jämförs med publicerat underlag; differensen ändrar inte intäkten automatiskt.'));
   if abs(workify-control)>0.005 then
    report:=jsonb_set(report,'{month,metrics,0,status}','"partial"'::jsonb);
    report:=jsonb_set(report,'{month,metrics,1,status}','"partial"'::jsonb);
    report:=jsonb_set(report,'{ytd,metrics,0,status}','"partial"'::jsonb);
    report:=jsonb_set(report,'{ytd,metrics,1,status}','"partial"'::jsonb);
   end if;
  end if;
 end if;
 report:=report||jsonb_build_object('correction_revision',revision);
 insert into private.hub_kpi_monthly_report_cache(tenant_id,generation_id,correction_revision,fiscal_year,month,cost_center,filters,report)
 values(p_tenant_id,generation,revision,p_fiscal_year,p_month,center,p_filters,report)on conflict do nothing;
 return private.hub_kpi_mapped_units_projection_v1(p_tenant_id,report);
end $function$
;

