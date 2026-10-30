CREATE OR REPLACE FUNCTION private.hub_allocate_saw_supplier_common_v1(p_tenant uuid,p_generation uuid) RETURNS void LANGUAGE plpgsql SET search_path TO '' SET jit TO 'off' AS $function$
declare
 r private.hub_saw_activity_rules_v1;
 f private.hub_kpi_prepared_facts;
 saw_part numeric; retained_part numeric; changed integer;
 before_totals jsonb; after_totals jsonb;
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'Access denied'using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||p_tenant::text,0));
 select * into r from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant;
 if not found then return; end if;
 if r.supplier_share is null or r.supplier_share<0 or r.supplier_share>1 then raise exception 'Invalid supplier share'; end if;
 select jsonb_agg(to_jsonb(t) order by fiscal_year,kind) into before_totals
 from(select fiscal_year,kind,sum(amount) amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation group by 1,2)t;
 -- Replace the former 50/25/25 branches, never add a second allocation.
 delete from private.hub_kpi_prepared_display_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_supplier_common';
 delete from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_supplier_common';
 for f in select * from private.hub_kpi_prepared_facts
 where tenant_id=p_tenant and generation_id=p_generation and kind='cost'
 and original#>>'{_humla_saw_activity,reason}'='supplier_work_full'
 and original#>>'{_humla_saw_activity,branch}'='retained'
 loop
  saw_part:=round((f.original#>>'{_humla_saw_activity,original_amount}')::numeric*r.supplier_share,2);
  retained_part:=(f.original#>>'{_humla_saw_activity,original_amount}')::numeric-saw_part;
  update private.hub_kpi_prepared_facts set
   amount=case when fact_id=f.fact_id then retained_part else saw_part end,
   cost_center=case when fact_id=f.fact_id then '10' else '30' end,
   unit_id=case when fact_id=f.fact_id then null else r.unit_id end,
   unit_name=case when fact_id=f.fact_id then null else 'Sågning' end,
   business_group=case when fact_id=f.fact_id then null else 'Sågning' end,
   vehicle=null,
   original=jsonb_set(jsonb_set(original,'{_humla_saw_activity,share}',to_jsonb(r.supplier_share)),'{_humla_saw_activity,allocated_amount}',to_jsonb(saw_part)),
   display_original=jsonb_set(jsonb_set(display_original,'{_humla_saw_activity,share}',to_jsonb(r.supplier_share)),'{_humla_saw_activity,allocated_amount}',to_jsonb(saw_part))
  where tenant_id=p_tenant and generation_id=p_generation and fact_id in(f.fact_id,f.fact_id||':saw');
  get diagnostics changed=row_count;
  if changed<>2 then raise exception 'Supplier source must have exactly two branches: %',f.fact_id; end if;
 end loop;
 delete from private.hub_kpi_prepared_display_facts d using private.hub_kpi_prepared_facts ff
 where ff.tenant_id=p_tenant and ff.generation_id=p_generation
 and ff.original#>>'{_humla_saw_activity,reason}'='supplier_work_full'
 and d.tenant_id=ff.tenant_id and d.generation_id=ff.generation_id and d.fact_id=ff.fact_id;
 insert into private.hub_kpi_prepared_display_facts
 select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original
 from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation
 and original#>>'{_humla_saw_activity,reason}'='supplier_work_full';
 select jsonb_agg(to_jsonb(t) order by fiscal_year,kind) into after_totals
 from(select fiscal_year,kind,sum(amount) amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation group by 1,2)t;
 if before_totals is distinct from after_totals then raise exception 'Supplier allocation changed financial totals';end if;
end $function$;