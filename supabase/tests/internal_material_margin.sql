-- Run as maintenance role. All fixture changes roll back.
begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';g uuid;r jsonb;before_result jsonb;after_result jsonb;fid text;sale numeric;cost numeric;
begin
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 r:=public.hub_kpi_internal_summary_v1(t,2026,array[9],'{"cost_center":"30"}');
 before_result:=r->'material_margin';
 assert (before_result->>'matched_rows')::int=(before_result->>'rows')::int,'All material rows must have a purchase calculation';
 assert (before_result->>'fallback_rows')::int>0,'Previously unresolved rows must use approved estimates';
 assert (before_result->>'billed')::numeric-(before_result->>'purchase_cost')::numeric=(before_result->>'difference')::numeric,'Margin must use same rows';
 assert (before_result->>'billed')::numeric-(before_result->>'bundled_billed')::numeric+(before_result->>'bundled_material_component')::numeric=(r->>'material')::numeric,'Coverage must reconcile to material card';
 assert private.hub_kpi_internal_material_margin_v1(t,2026,array[9],'{"kind":"cost"}')->>'difference' is null,'Cost filter must not leak revenue';
 select fact_id,amount,(original#>>'{_humla_material_separation,purchase,amount}')::numeric into fid,sale,cost
 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and fiscal_year=2026 and occurred_on between '2026-09-01' and '2026-09-30'
 and cost_center='30' and source='Workify' and kind='revenue' and category='material' and original->>'Orderstatus'='Invoiced'
 and lower(trim(display_original#>>'{_humla_invoice,customer_name}'))='elleholms maskin ab'
 and original#>>'{_humla_material_separation,method}'='material_article'
 and amount>0 and (original#>>'{_humla_material_separation,purchase,amount}')::numeric>0 limit 1;
 assert fid is not null,'Expected positive fixture';
 update private.hub_kpi_prepared_facts set amount=-sale,original=jsonb_set(original,'{_humla_material_separation,purchase,amount}',to_jsonb(-cost)) where tenant_id=t and generation_id=g and fact_id=fid;
 after_result:=private.hub_kpi_internal_material_margin_v1(t,2026,array[9],'{"cost_center":"30"}');
 assert (after_result->>'difference')::numeric=(before_result->>'difference')::numeric-2*(sale-cost),'Credit must reverse both selling price and purchase';
 update private.hub_kpi_prepared_facts set original=jsonb_set(original,'{_humla_material_separation,purchase,amount}',to_jsonb(cost)) where tenant_id=t and generation_id=g and fact_id=fid;
 after_result:=private.hub_kpi_internal_material_margin_v1(t,2026,array[9],'{"cost_center":"30"}');
 assert (after_result->>'missing_rows')::int=(before_result->>'missing_rows')::int+1,'Opposite purchase sign must be reviewed';
 assert (after_result->>'rows')::int=(before_result->>'rows')::int,'Review must retain every revenue row';
 assert after_result->>'difference' is null,'Incomplete costs must not be treated as zero';
 update private.hub_kpi_prepared_facts set amount=sale,original=jsonb_set(original,'{_humla_material_separation,method}','"purchase_price_transport_remainder"') where tenant_id=t and generation_id=g and fact_id=fid;
 after_result:=private.hub_kpi_internal_material_margin_v1(t,2026,array[9],'{"cost_center":"30"}');
 assert (after_result->>'bundled_rows')::int=(before_result->>'bundled_rows')::int+1,'Bundled transport must be labelled';
 assert (after_result->>'matched_rows')::int=(before_result->>'matched_rows')::int,'Bundled rows must stay in the calculation';
 assert (after_result->>'billed')::numeric=(before_result->>'billed')::numeric,'Bundled source selling price must be counted once';
end $$;
rollback;
