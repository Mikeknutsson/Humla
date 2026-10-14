-- Financial cards must not use bookkeeping export readiness as a revenue gate.
create or replace function private.hub_kpi_internal_overview_v1(p_tenant_id uuid,p_fiscal_year integer,p_months integer[],p_filters jsonb)
returns jsonb language plpgsql stable security invoker set search_path='' set jit='off' set plan_cache_mode='force_custom_plan' as $$
declare generation uuid;months integer[];answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')then
  raise exception 'KPI access required'using errcode='42501';end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_months);
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then raise exception 'Prepared report required';end if;
 with scoped as materialized(
  select f.fact_id,f.amount,f.category,
   coalesce(f.original->>'_humla_workify_source_row_id',split_part(f.fact_id,':',1)) source_row,
   f.original->>'Orderstatus'='Invoiced' invoiced,
   (f.unit_id is null or f.cost_center='unclassified' or f.category not in('transport','material','tipp_deponi')) needs_classification
  from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant_id and f.generation_id=generation
   and f.fiscal_year=p_fiscal_year and extract(month from f.occurred_on)::integer=any(months)
   and f.source='Workify' and f.kind='revenue'
   and lower(trim(f.original->>'Kundnamn'))='elleholms maskin ab'
   and (not(p_filters?'cost_center') or f.cost_center=any(string_to_array(p_filters->>'cost_center',',')))
   and (not(p_filters?'group') or f.business_group=any(string_to_array(p_filters->>'group',',')))
   and (not(p_filters?'unit') or f.unit_id::text=p_filters->>'unit' or p_filters->>'unit'='vehicle:'||f.vehicle)
   and (not(p_filters?'vehicle') or f.vehicle=p_filters->>'vehicle')
   and (not(p_filters?'project') or f.project=p_filters->>'project')
   and (not(p_filters?'category') or f.category=p_filters->>'category')
   and (not(p_filters?'kind') or p_filters->>'kind'='revenue')
   and (not(p_filters?'source') or p_filters->>'source'='Workify')
   and (not(p_filters?'date_from') or f.occurred_on>=(p_filters->>'date_from')::date)
   and (not(p_filters?'date_to') or f.occurred_on<=(p_filters->>'date_to')::date)
 )select jsonb_build_object(
  'scope','published_generation','generation',generation,
  'total',coalesce(sum(amount)filter(where invoiced),0),
  'material',coalesce(sum(amount)filter(where invoiced and category='material'),0),
  'tipp_deponi',coalesce(sum(amount)filter(where invoiced and category='tipp_deponi'),0),
  'transport',coalesce(sum(amount)filter(where invoiced and category='transport'),0),
  'other',coalesce(sum(amount)filter(where invoiced and category not in('material','tipp_deponi','transport')),0),
  'rows',count(distinct source_row)filter(where invoiced),
  'review_rows',count(distinct source_row)filter(where invoiced and needs_classification),
  'review_amount',coalesce(sum(amount)filter(where invoiced and needs_classification),0),
  'review_included',true,
  'pending_rows',count(distinct source_row)filter(where invoiced is not true),
  'pending_amount',coalesce(sum(amount)filter(where invoiced is not true),0),
  'basis','Fakturerade Workify-intäkter med kund Elleholms Maskin AB, från samma publicerade och dubblettskyddade underlag som KPI. Period och kostnadsställe följer KPI-raderna. Material och transport följer Hubbens fördelning. Dessa internintäkter ingår redan i KPI-omsättningen och är inga externa inbetalningar. Bokförings- och exportstatus kontrolleras separat och ändrar inte kortens belopp.')into answer from scoped;
 return answer;
end $$;
revoke all on function private.hub_kpi_internal_overview_v1(uuid,integer,integer[],jsonb) from public,anon;

-- Invalidate existing summaries without starting a full report worker.
update private.hub_kpi_report_state set correction_revision=correction_revision+1
where active_generation is not null;
