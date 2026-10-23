-- Caller sets task.tenant_id and a verified KPI manager JWT subject.
do $$
declare t uuid:=current_setting('task.tenant_id')::uuid;g uuid;target uuid;material uuid;legacy uuid;old_count bigint;old_amount numeric;n integer;
begin
 if auth.uid() is null or not public.hub_has_permission(t,'kpi.manage') then raise exception 'KPI management required';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0)) then raise exception 'Report worker busy';end if;
 select active_generation into strict g from private.hub_kpi_report_state where tenant_id=t for update;
 select u.id into strict target from public.kpi_units u join public.hub_objects h on h.id=u.id and h.tenant_id=u.tenant_id and h.object_type='EconomicUnit'
 where u.tenant_id=t and u.enabled and u.origin in('manual','manual_builder') and 'ZLA906'=any(u.registrations);
 insert into private.hub_workify_article_unit_rules(tenant_id,article_contains,target_unit_id,valid_from,approval_reference,created_by)
 values(t,'hjullastare',target,'2025-09-01','Mike: all articles containing hjullastare belong to ZLA906, 2026-10-14',auth.uid())
 on conflict(tenant_id,article_contains,valid_from) do update set target_unit_id=excluded.target_unit_id,enabled=true,approval_reference=excluded.approval_reference;
 n:=private.hub_apply_workify_article_units_v1(t,g);
 select u.id into strict material from public.kpi_units u join public.hub_objects h on h.id=u.id and h.tenant_id=u.tenant_id and h.object_type='EconomicUnit'
 where u.tenant_id=t and u.enabled and u.origin in('manual','manual_builder') and u.unit_type='project' and u.projects=array['4004']::text[];
 select material_unit_id into strict legacy from private.hub_kpi_material_separation_settings where tenant_id=t for update;
 select count(*),sum(amount)into old_count,old_amount from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g;
 if legacy<>material then
  if exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and unit_id=legacy and project is distinct from '4004') then raise exception 'Legacy material unit has unrelated projects';end if;
  insert into private.hub_article_unit_routing_audit(tenant_id,generation_id,fact_id,before_record,after_record,actor)
  select t,g,f.fact_id,to_jsonb(f),jsonb_build_object('unit_id',material,'reason','consolidate_confirmed_material_unit'),auth.uid()
  from private.hub_kpi_prepared_facts f where f.tenant_id=t and f.generation_id=g and f.unit_id=legacy and f.project='4004' on conflict do nothing;
  update private.hub_kpi_prepared_facts f set unit_id=material,unit_name=u.name,
   classification_source=coalesce(f.classification_source,'{}')||jsonb_build_object('material_unit_consolidated',true)
  from public.kpi_units u where u.id=material and f.tenant_id=t and f.generation_id=g and f.unit_id=legacy and f.project='4004';
  update private.hub_kpi_prepared_display_facts f set unit_id=material,unit_name=u.name from public.kpi_units u
  where u.id=material and f.tenant_id=t and f.generation_id=g and f.unit_id=legacy and f.project='4004';
  update private.hub_kpi_material_separation_settings set material_unit_id=material where tenant_id=t;
 end if;
 if row(old_count,old_amount) is distinct from (select row(count(*),sum(amount))from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g)then raise exception 'Material consolidation changed financial totals';end if;
 update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=t;
 raise notice 'Article facts routed: %',n;
end $$;
