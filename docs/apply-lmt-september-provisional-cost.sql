-- Maintenance caller sets task.tenant_id and a verified manager JWT subject.
do $$
declare t uuid:=current_setting('task.tenant_id')::uuid;g uuid;u uuid;a numeric;ids jsonb;r jsonb;before_cost numeric;after_cost numeric;already boolean;
begin
 if auth.uid() is null or not public.hub_has_permission(t,'kpi.manage')then raise exception 'KPI management required';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0))then raise exception 'Worker busy';end if;
 select active_generation into strict g from private.hub_kpi_report_state where tenant_id=t for update;
 select k.id into strict u from public.kpi_units k join public.hub_objects h on h.id=k.id and h.tenant_id=k.tenant_id and h.object_type='EconomicUnit'
 where k.tenant_id=t and k.enabled and 'LMT31J'=any(k.registrations) and k.origin in('manual','manual_builder');
 if exists(select 1 from public.kpi_import_rows where tenant_id=t and data_kind='cost' and is_valid and occurred_on between '2026-09-01' and '2026-09-30'
 and upper(trim(source_data->>'Leverantör'))='ERIK IVARSSON ENSKILD FIRMA')then raise exception 'September supplier cost already imported; use actual evidence';end if;
 select sum(amount),jsonb_agg(fact_id order by fact_id)into a,ids from private.hub_kpi_prepared_facts
 where tenant_id=t and generation_id=g and source='NEXT' and kind='cost' and unit_id=u and occurred_on between '2026-08-01' and '2026-08-31'
 and upper(trim(original->>'Leverantör'))='ERIK IVARSSON ENSKILD FIRMA';
 if a is null or a<=0 then raise exception 'Verified August supplier amount missing';end if;
 select coalesce(sum(amount),0)into before_cost from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and kind='cost';
 already:=exists(select 1 from private.hub_kpi_provisional_supplier_costs e join private.hub_kpi_prepared_facts f on f.fact_id='provisional-supplier-cost:'||e.id::text
 where e.tenant_id=t and e.unit_id=u and e.month_start='2026-09-01' and f.tenant_id=t and f.generation_id=g);
 insert into private.hub_kpi_provisional_supplier_costs(tenant_id,unit_id,supplier_name,month_start,amount,basis,approved_by)
 values(t,u,'Erik Ivarsson Enskild firma','2026-09-01',a,
 jsonb_build_object('reference_month','2026-08','reference_fact_ids',ids,'reference_generation',g,'method','same_as_previous_month',
 'approval','Mike 2026-10-14: missing September invoice; use August amount on LMT31J'),auth.uid())
 on conflict(tenant_id,unit_id,supplier_name,month_start)do nothing;
 r:=private.hub_kpi_publish_provisional_supplier_costs_v1(t,g);
 select coalesce(sum(amount),0)into after_cost from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and kind='cost';
 if after_cost-before_cost<>(case when already then 0 else a end) then raise exception 'Unexpected cost difference';end if;
 if after_cost<>before_cost then update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=t;end if;
end $$;
