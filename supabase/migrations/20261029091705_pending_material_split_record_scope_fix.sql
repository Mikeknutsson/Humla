create or replace function private.hub_resolve_pending_material_prices_v1(p_tenant uuid,p_generation uuid,p_rows uuid[])
returns jsonb language plpgsql set search_path='' set jit='off' as $fn$
#variable_conflict use_column
declare f record;d private.hub_kpi_prepared_display_facts;cfg record;prices jsonb;e jsonb;part numeric;allocation jsonb;n int:=0;skipped int:=0;before_money jsonb;after_money jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then raise exception 'KPI management required' using errcode='42501';end if;
 if cardinality(p_rows)>1000 or p_rows is null then raise exception 'Invalid rows';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant)then raise exception 'Generation mismatch';end if;
 select s.material_unit_id,u.name,u.projects[1] project into strict cfg from private.hub_kpi_material_separation_settings s join public.kpi_units u on u.id=s.material_unit_id and u.tenant_id=s.tenant_id
 join public.hub_objects h on h.id=u.id and h.tenant_id=s.tenant_id and h.object_type='EconomicUnit' where s.tenant_id=p_tenant and s.enabled;
 select jsonb_build_object('revenue',sum(amount)filter(where kind='revenue'),'cost',sum(amount)filter(where kind='cost')) into before_money from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 prices:=private.hub_kpi_material_purchase_costs_v1(p_tenant,p_rows);
 for f in select f.* from private.hub_kpi_prepared_facts f join public.hub_objects o on o.id=f.unit_id and o.tenant_id=f.tenant_id and o.object_type='EconomicUnit'
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=any(array(select x::text from unnest(p_rows)x))
 and f.source='Workify' and f.kind='revenue' and f.original#>>'{_humla_material_separation,status}'='needs_review'
 and o.data->>'unit_type' in('vehicle','compound') and concat_ws(' ',f.original->>'Artikelnamn',f.description) ~* 'in[ck]l?[.]?[[:space:]]*transport'
 loop
  e:=prices->f.fact_id;part:=(e->>'amount')::numeric;
  if part is null or part<0 or part>f.amount or e->>'status' not in('receipt_price_list','project_price_override','preliminary_source','average_estimate')
   or(e->>'status'='average_estimate' and coalesce((e->>'price_sample_count')::int,0)<>3) then skipped:=skipped+1;continue;end if;
  if exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and fact_id=f.fact_id||':material')then raise exception 'Already split';end if;
  select * into strict d from private.hub_kpi_prepared_display_facts where tenant_id=p_tenant and generation_id=p_generation and fact_id=f.fact_id;
  allocation:=jsonb_build_object('method','purchase_price_transport_remainder','original_fact_id',f.fact_id,'original_amount',f.amount,'original_vehicle',f.vehicle,'original_unit_id',f.unit_id,'original_project',f.project,'purchase',e,'estimated',e->>'status' in('average_estimate','preliminary_source'),'previous_review',f.original->'_humla_material_separation');
  insert into private.hub_kpi_prepared_facts select(jsonb_populate_record(null::private.hub_kpi_prepared_facts,to_jsonb(f)||jsonb_build_object('fact_id',f.fact_id||':material','amount',part,'category','material','unit_id',cfg.material_unit_id,'unit_name',cfg.name,'vehicle',null,'project',cfg.project,'business_group','Grusmaterial','original',f.original||jsonb_build_object('_humla_material_separation',allocation||jsonb_build_object('component','material')),'display_original',coalesce(f.display_original,'{}')||jsonb_build_object('_humla_material_separation',allocation||jsonb_build_object('component','material'))))).*;
  update private.hub_kpi_prepared_facts set amount=f.amount-part,category='transport',original=f.original||jsonb_build_object('_humla_material_separation',allocation||jsonb_build_object('component','transport')),display_original=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_material_separation',allocation||jsonb_build_object('component','transport')) where tenant_id=p_tenant and generation_id=p_generation and fact_id=f.fact_id;
  insert into private.hub_kpi_prepared_display_facts select(jsonb_populate_record(null::private.hub_kpi_prepared_display_facts,to_jsonb(d)||jsonb_build_object('fact_id',f.fact_id||':material','amount',part,'category','material','unit_id',cfg.material_unit_id,'unit_name',cfg.name,'vehicle',null,'project',cfg.project,'business_group','Grusmaterial','original',coalesce(d.original,'{}')||jsonb_build_object('_humla_material_separation',allocation||jsonb_build_object('component','material'))))).*;
  update private.hub_kpi_prepared_display_facts set amount=f.amount-part,category='transport',original=coalesce(d.original,'{}')||jsonb_build_object('_humla_material_separation',allocation||jsonb_build_object('component','transport')) where tenant_id=p_tenant and generation_id=p_generation and fact_id=f.fact_id;
  n:=n+1;
 end loop;
 select jsonb_build_object('revenue',sum(amount)filter(where kind='revenue'),'cost',sum(amount)filter(where kind='cost')) into after_money from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 if before_money is distinct from after_money then raise exception 'Financial totals changed';end if;
 return jsonb_build_object('split_rows',n,'skipped_rows',skipped,'financial_totals_unchanged',true);
end $fn$;
revoke all on function private.hub_resolve_pending_material_prices_v1(uuid,uuid,uuid[]) from public,anon,authenticated;