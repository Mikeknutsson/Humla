-- Include all material rows; use existing approved overview estimates where exact purchase evidence is unresolved.
-- Compare selling price and purchase cost on the same published material rows.
create or replace function private.hub_kpi_internal_material_margin_v1(p_tenant_id uuid,p_fiscal_year integer,p_months integer[],p_filters jsonb)
returns jsonb language plpgsql stable security invoker set search_path='' set jit='off' set plan_cache_mode='force_custom_plan' as $$
declare generation uuid;months integer[];answer jsonb;date_from date;date_to date;scope_rows jsonb;fallback jsonb:='{}';batch record;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')then
  raise exception 'KPI access required'using errcode='42501';end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_months);
 select min(make_date(p_fiscal_year+case when m<9 then 1 else 0 end,m,1)),(max(make_date(p_fiscal_year+case when m<9 then 1 else 0 end,m,1))+interval '1 month - 1 day')::date into date_from,date_to from unnest(months)m;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then raise exception 'Prepared report required';end if;
 with scoped as materialized(
  select distinct on (coalesce(f.original->>'_humla_workify_source_row_id',split_part(f.fact_id,':',1)))
   coalesce(f.original->>'_humla_workify_source_row_id',split_part(f.fact_id,':',1)) source_row,
   f.occurred_on,f.original->>'Ordernummer' order_number,f.original->>'Artikelnamn' article,
   f.amount material_amount,
   case when f.original#>>'{_humla_material_separation,method}'='purchase_price_transport_remainder'
    then (f.original#>>'{_humla_material_separation,original_amount}')::numeric else f.amount end billed,
   coalesce(f.original#>>'{_humla_material_separation,method}'='purchase_price_transport_remainder',false) bundled,
   f.original#>'{_humla_material_separation,purchase}' evidence
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
 )select coalesce(jsonb_agg(to_jsonb(scoped)),'[]'::jsonb) into scope_rows from scoped;
 -- Use the existing approved overview-estimate rule for unresolved published prices.
 -- Batch below the public helper limit, preserving tenant isolation and raw source rows.
 for batch in
  select array_agg(id) ids from (
   select source_row::uuid id,(row_number()over(order by source_row)-1)/1000 bucket
   from jsonb_to_recordset(scope_rows)r(source_row text,evidence jsonb)
   where evidence->>'amount' is null and source_row ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  )q group by bucket
 loop
  fallback:=fallback||public.hub_kpi_internal_purchase_costs_v1(p_tenant_id,batch.ids);
 end loop;
 with priced as (
  select r.*,case when evidence->>'amount' is null then fallback->source_row else evidence end selected_evidence,
   evidence->>'amount' is null and fallback#>>array[source_row,'amount'] is not null used_fallback
  from jsonb_to_recordset(scope_rows)r(source_row text,occurred_on date,order_number text,article text,material_amount numeric,billed numeric,bundled boolean,evidence jsonb)
 ), costs as (
  select *,case when (selected_evidence->>'amount')::numeric=0
   or sign((selected_evidence->>'amount')::numeric)=sign(billed)
   then (selected_evidence->>'amount')::numeric end purchase from priced
 )select jsonb_build_object(
 'billed',sum(billed),
 'purchase_cost',case when count(*)filter(where purchase is null)=0 then sum(purchase) end,
 'difference',case when count(*)filter(where purchase is null)=0 then sum(billed-purchase) end,
 'margin_percent',case when count(*)filter(where purchase is null)=0 then round(sum(billed-purchase)/nullif(sum(billed),0)*100,2) end,
 'rows',count(*),'matched_rows',count(*)filter(where purchase is not null),
 'estimated_rows',count(*)filter(where purchase is not null and selected_evidence->>'status' is distinct from 'receipt_price_list'),
 'fallback_rows',count(*)filter(where used_fallback),
 'fallback_billed',coalesce(sum(billed)filter(where used_fallback),0),
 'fallback_purchase',coalesce(sum(purchase)filter(where used_fallback),0),
 'missing_rows',count(*)filter(where purchase is null),
 'missing_billed',coalesce(sum(billed)filter(where purchase is null),0),
 'bundled_rows',count(*)filter(where bundled),
 'bundled_material_component',coalesce(sum(material_amount)filter(where bundled),0),
 'bundled_billed',coalesce(sum(billed)filter(where bundled),0),
 'details',coalesce(jsonb_agg(jsonb_build_object('source_row',source_row,'date',occurred_on,'order_number',order_number,'article',article,
  'billed',billed,'purchase_cost',purchase,'difference',billed-purchase,'fallback',used_fallback,'bundled',bundled,'evidence',selected_evidence)
  order by occurred_on,order_number,source_row),'[]'::jsonb),
 'basis','Alla fakturerade interna materialrader i urvalet ingår. Mellanskillnad = fakturerat internpris minus beräknat inköp för samma rader. Saknas entydigt pris används Hubbens befintliga överslagsregel: tillgängligt medelpris för fraktionen, annars grovt medelpris per samma enhet. Prislistor och schabloner är inte verifierade leverantörsfakturor. Om pris inte kan beräknas visas hela internpriset och ofullständigt kostnadsunderlag; okänd kostnad sätts inte till noll.'
 )into answer from costs;
 return answer;
end $$;
revoke all on function private.hub_kpi_internal_material_margin_v1(uuid,integer,integer[],jsonb) from public,anon,authenticated;
