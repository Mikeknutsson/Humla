-- Compare selling price and purchase cost on the same published material rows.
create or replace function private.hub_kpi_internal_material_margin_v1(p_tenant_id uuid,p_fiscal_year integer,p_months integer[],p_filters jsonb)
returns jsonb language plpgsql stable security invoker set search_path='' set jit='off' set plan_cache_mode='force_custom_plan' as $$
declare generation uuid;months integer[];answer jsonb;date_from date;date_to date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')then
  raise exception 'KPI access required'using errcode='42501';end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_months);
 select min(make_date(p_fiscal_year+case when m<9 then 1 else 0 end,m,1)),(max(make_date(p_fiscal_year+case when m<9 then 1 else 0 end,m,1))+interval '1 month - 1 day')::date into date_from,date_to from unnest(months)m;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then raise exception 'Prepared report required';end if;
 with scoped as materialized(
  select distinct on (coalesce(f.original->>'_humla_workify_source_row_id',split_part(f.fact_id,':',1)))
   f.fact_id,f.amount,
   f.original#>>'{_humla_material_separation,method}'='purchase_price_transport_remainder' bundled,
   (f.original#>>'{_humla_material_separation,purchase,amount}')::numeric purchase_cost,
   f.original#>>'{_humla_material_separation,purchase,status}' purchase_status
  from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant_id and f.generation_id=generation
   and f.fiscal_year=p_fiscal_year and f.occurred_on between date_from and date_to and extract(month from f.occurred_on)::integer=any(months)
   and f.source='Workify' and f.kind='revenue' and f.category='material' and f.original->>'Orderstatus'='Invoiced'
   and lower(trim(f.display_original#>>'{_humla_invoice,customer_name}'))='elleholms maskin ab'
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
 ), classified as (
 select *, bundled is not true and purchase_cost is not null
  and (purchase_cost=0 or sign(purchase_cost)=sign(amount)) matched from scoped
 )select jsonb_build_object(
 'billed',sum(amount)filter(where matched),
 'purchase_cost',sum(purchase_cost)filter(where matched),
 'difference',sum(amount-purchase_cost)filter(where matched),
 'margin_percent',round(sum(amount-purchase_cost)filter(where matched)/nullif(sum(amount)filter(where matched),0)*100,2),
 'matched_rows',count(*)filter(where matched),
 'estimated_rows',count(*)filter(where matched and purchase_status is distinct from 'receipt_price_list'),
 'missing_rows',count(*)filter(where not matched and bundled is not true),
 'missing_billed',coalesce(sum(amount)filter(where not matched and bundled is not true),0),
 'bundled_rows',count(*)filter(where bundled),
 'bundled_material_component',coalesce(sum(amount)filter(where bundled),0),
 'basis','Fakturerat internpris för separata materialrader minus inköpskostnad enligt publicerat prisunderlag, för samma rader. Prislistor och schabloner är inte verifierade leverantörsfakturor. Rader utan inköpsunderlag samt material inklusive transport ingår inte i mellanskillnaden.'
 )into answer from classified;
 return answer;
end $$;
revoke all on function private.hub_kpi_internal_material_margin_v1(uuid,integer,integer[],jsonb) from public,anon,authenticated;

-- Display a Hub-calculated remainder without changing revenue facts.
create or replace function public.hub_kpi_internal_summary_v1(p_tenant uuid,p_year integer,p_months integer[],p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' as $$
declare result jsonb;revenue numeric;remainder numeric;
begin
 result:=private.hub_kpi_internal_overview_v1(p_tenant,p_year,private.hub_kpi_month_scope_v1(p_year,p_months),p_filters);
 revenue:=(private.hub_kpi_prepared_comparison_v1(p_tenant,p_year,p_months,p_filters)#>>'{metrics,revenue}')::numeric;
 remainder:=(result->>'total')::numeric-(result->>'material')::numeric-(result->>'tipp_deponi')::numeric;
 return result||jsonb_build_object('revenue_basis',revenue,
 'total_percent',round((result->>'total')::numeric/nullif(revenue,0)*100,2),
 'material_percent',round((result->>'material')::numeric/nullif(revenue,0)*100,2),
 'tipp_deponi_percent',round((result->>'tipp_deponi')::numeric/nullif(revenue,0)*100,2),
 'material_margin',private.hub_kpi_internal_material_margin_v1(p_tenant,p_year,p_months,p_filters),
 'remaining',remainder,'remaining_percent',round(remainder/nullif(revenue,0)*100,2));
end $$;
revoke all on function public.hub_kpi_internal_summary_v1(uuid,integer,integer[],jsonb) from public,anon;
grant execute on function public.hub_kpi_internal_summary_v1(uuid,integer,integer[],jsonb) to authenticated;
