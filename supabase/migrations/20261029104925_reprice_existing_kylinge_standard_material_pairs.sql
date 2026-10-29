create or replace function private.hub_reprice_standard_material_pairs_v1(p_tenant uuid,p_generation uuid,p_rows uuid[])
returns jsonb language plpgsql set search_path='' set jit='off' as $fn$
declare rec record;prices jsonb;e jsonb;part numeric;audit jsonb;n int:=0;delta numeric:=0;before_money jsonb;after_money jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'KPI management required' using errcode='42501';end if;
 if p_rows is null or cardinality(p_rows)>1000 then raise exception 'Invalid rows';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where tenant_id=p_tenant and id=p_generation)then raise exception 'Generation mismatch';end if;
 select jsonb_build_object('revenue',sum(amount)filter(where kind='revenue'),'cost',sum(amount)filter(where kind='cost')) into before_money from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 prices:=private.hub_kpi_material_purchase_costs_v1(p_tenant,p_rows);
 for rec in select f.fact_id,f.amount transport,m.amount material,f.original#>'{_humla_material_separation,purchase}' previous_purchase
 from private.hub_kpi_prepared_facts f join private.hub_kpi_prepared_facts m on m.tenant_id=f.tenant_id and m.generation_id=f.generation_id and m.fact_id=f.fact_id||':material'
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=any(array(select x::text from unnest(p_rows)x)) and f.category='transport' and m.category='material' loop
  e:=prices->rec.fact_id;part:=(e->>'amount')::numeric;
  if coalesce((e->>'standard_project_fallback')::boolean,false) is not true or e->>'status'<>'preliminary_source' or part is null or part<0 or part>rec.transport+rec.material or part=rec.material then continue;end if;
  audit:=jsonb_build_object('reason','Owner-approved Kylinge standard fallback when project material price is missing','old_material',rec.material,'new_material',part,'old_transport',rec.transport,'new_transport',rec.transport+rec.material-part,'previous_purchase',rec.previous_purchase,'actor',auth.uid(),'at',now());
  update private.hub_kpi_prepared_facts f set amount=case when f.fact_id=rec.fact_id then rec.transport+rec.material-part else part end,
   original=jsonb_set(f.original,'{_humla_material_separation,purchase}',e,true)||jsonb_build_object('_humla_material_reprice',audit),
   display_original=jsonb_set(coalesce(f.display_original,'{}'),'{_humla_material_separation,purchase}',e,true)||jsonb_build_object('_humla_material_reprice',audit)
  where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id in(rec.fact_id,rec.fact_id||':material');
  update private.hub_kpi_prepared_display_facts d set amount=f.amount,original=f.display_original from private.hub_kpi_prepared_facts f
   where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id in(rec.fact_id,rec.fact_id||':material') and d.tenant_id=f.tenant_id and d.generation_id=f.generation_id and d.fact_id=f.fact_id;
  if(select sum(amount) from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and fact_id in(rec.fact_id,rec.fact_id||':material'))<>rec.transport+rec.material then raise exception 'Pair sum changed';end if;
  n:=n+1;delta:=delta+part-rec.material;
 end loop;
 select jsonb_build_object('revenue',sum(amount)filter(where kind='revenue'),'cost',sum(amount)filter(where kind='cost')) into after_money from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 if before_money is distinct from after_money then raise exception 'Financial totals changed';end if;
 return jsonb_build_object('repriced_pairs',n,'material_delta',delta,'financial_totals_unchanged',true);
end $fn$;
revoke all on function private.hub_reprice_standard_material_pairs_v1(uuid,uuid,uuid[]) from public,anon,authenticated;