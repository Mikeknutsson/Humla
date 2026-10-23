-- Run once through the maintenance connection with task.tenant_id and a
-- verified KPI manager JWT subject set transaction-locally by the caller.
-- Correct existing mappings in place; never delete raw imports or transactions.
do $$
declare
 tenant uuid:=current_setting('task.tenant_id')::uuid;
 generation uuid; operation uuid:=gen_random_uuid(); r record; recipient record;
 corrected integer; displayed integer;
begin
 if auth.uid() is null or not public.hub_has_permission(tenant,'kpi.manage') then
  raise exception 'KPI management access required';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0)) then
  raise exception 'Report worker busy';end if;
 select active_generation into generation from private.hub_kpi_report_state
 where tenant_id=tenant for update;
 if generation is null then raise exception 'Prepared report required';end if;
 if not exists(select 1 from public.kpi_dashboard_allocations a
  where a.tenant_id=tenant and a.source='Workify' and a.kind='revenue'
  and a.reference_type='project' and a.reference='5100'
  and a.dimension='project' and a.target='12716')then return;end if;

 -- Resolve a canonical, dated recipient for every historical fact first.
 for r in select f.* from private.hub_kpi_prepared_facts f
 where f.tenant_id=tenant and f.generation_id=generation and f.source='Workify'
 and f.kind='revenue' and f.project='12716' and f.original->>'_humla_original_project'='5100'
 and exists(select 1 from public.kpi_dashboard_allocations a where a.tenant_id=tenant
  and a.source='Workify' and a.kind='revenue' and a.reference_type='project'
  and a.reference='5100' and a.dimension='project' and a.target='12716'
  and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on))
 loop
  if exists(select 1 from public.kpi_dashboard_allocations a where a.tenant_id=tenant
   and a.source='Workify' and a.kind='revenue' and a.reference_type='fact'
   and a.reference=r.fact_id and a.dimension in('project','unit','group','category')
   and a.valid_from<=r.occurred_on and (a.valid_to is null or a.valid_to>=r.occurred_on)) then
   raise exception 'Individual fact override requires review';end if;
  select count(distinct u.id) n,(array_agg(distinct u.id))[1] id,
   max(p.payload->>'name') name,max(g.name) grp into recipient
  from public.kpi_units u join public.hub_objects h on h.id=u.id
   and h.tenant_id=u.tenant_id and h.object_type='EconomicUnit'
  join public.kpi_unit_periods p on p.unit_id=u.id and p.tenant_id=u.tenant_id
   and p.valid_from<=r.occurred_on and (p.valid_to is null or p.valid_to>=r.occurred_on)
  join public.kpi_business_groups g on g.id::text=p.payload->>'business_group_id'
   and g.tenant_id=u.tenant_id and g.enabled
  where u.tenant_id=tenant and u.origin in('manual','manual_builder')
   and (p.payload->>'enabled')::boolean and p.payload->'projects' ? '5100';
  if recipient.n<>1 or recipient.name is null or recipient.grp is null then
   raise exception 'Trading requires one confirmed dated economic unit';end if;
  insert into private.hub_trading_destination_audit_v1
   (operation_id,tenant_id,generation_id,record_kind,record_key,before_record,after_record,actor)
  values(operation,tenant,generation,'prepared_fact',r.fact_id,to_jsonb(r),
   to_jsonb(r)||jsonb_build_object('project','5100','unit_id',recipient.id,
    'unit_name',recipient.name,'vehicle',null,'business_group',recipient.grp),auth.uid());
 end loop;

 -- Keep the rules and their dates; change only the incorrect destinations.
 insert into private.hub_trading_destination_audit_v1
 (operation_id,tenant_id,generation_id,record_kind,record_key,before_record,after_record,actor)
 select operation,tenant,generation,'dashboard_rule',a.id::text,to_jsonb(a),
  to_jsonb(a)||jsonb_build_object('target',case when dimension='project' then '5100' else 'Återvinning' end),auth.uid()
 from public.kpi_dashboard_allocations a where a.tenant_id=tenant
 and a.source='Workify' and a.kind='revenue' and a.reference_type='project' and a.reference='5100'
 and ((dimension='project' and target='12716') or (dimension='group' and target='Rivning'));
 update public.kpi_dashboard_allocations a set target=x.after_record->>'target',
 reason=coalesce(a.reason,'')||'; Trading destination corrected by user 2026-10-14'
 from private.hub_trading_destination_audit_v1 x where x.operation_id=operation
 and x.record_kind='dashboard_rule' and x.record_key=a.id::text;

 -- The approved article-file names identify disposal rather than transport.
 insert into private.hub_trading_destination_audit_v1
 (operation_id,tenant_id,generation_id,record_kind,record_key,before_record,after_record,actor)
 select operation,tenant,generation,'article_rule',a.id::text,to_jsonb(a),
  to_jsonb(a)||jsonb_build_object('revenue_category','tipp_deponi'),auth.uid()
 from public.kpi_workify_article_rules a where a.tenant_id=tenant and a.enabled
 and a.project_reference='5100' and a.revenue_category is distinct from 'tipp_deponi'
 and jsonb_array_length(a.source_rows)>0 and not exists(
  select 1 from jsonb_array_elements(a.source_rows)s
  where coalesce(s#>>'{values,Namn}','') !~* '^(Tippavgift|Behandlingsavgift)');
 update public.kpi_workify_article_rules a set revenue_category='tipp_deponi'
 from private.hub_trading_destination_audit_v1 x where x.operation_id=operation
 and x.record_kind='article_rule' and x.record_key=a.id::text;

 update private.hub_kpi_prepared_facts f set project='5100',
 unit_id=(x.after_record->>'unit_id')::uuid,unit_name=x.after_record->>'unit_name',
 vehicle=null,business_group=x.after_record->>'business_group',
 category=case when f.description ~* '^(Tippavgift|Behandlingsavgift)' then 'tipp_deponi' else f.category end,
 original=f.original||jsonb_build_object('_humla_project_assignment','5100',
  '_humla_assignment',coalesce(f.original->'_humla_assignment','{}'::jsonb)
   ||jsonb_build_object('project','5100','group',x.after_record->>'business_group'),
  '_humla_trading_destination_correction',operation),
 display_original=f.display_original||jsonb_build_object('_humla_project_assignment','5100',
  '_humla_assignment',coalesce(f.original->'_humla_assignment','{}'::jsonb)
   ||jsonb_build_object('project','5100','group',x.after_record->>'business_group'),
  '_humla_trading_destination_correction',operation),
 classification_source=f.classification_source||jsonb_build_object('manual_assignment',
  coalesce(f.original->'_humla_assignment','{}'::jsonb)
   ||jsonb_build_object('project','5100','group',x.after_record->>'business_group'),
  'reason','confirmed_trading_destination_restored')
 from private.hub_trading_destination_audit_v1 x where x.operation_id=operation
 and x.record_kind='prepared_fact' and x.record_key=f.fact_id
 and f.tenant_id=tenant and f.generation_id=generation;
 get diagnostics corrected=row_count;
 update private.hub_kpi_prepared_display_facts d set project=f.project,unit_id=f.unit_id,
 unit_name=f.unit_name,vehicle=f.vehicle,business_group=f.business_group,
 category=f.category,original=f.display_original
 from private.hub_kpi_prepared_facts f join private.hub_trading_destination_audit_v1 x
 on x.operation_id=operation and x.record_kind='prepared_fact' and x.record_key=f.fact_id
 where f.tenant_id=tenant and f.generation_id=generation
 and d.tenant_id=tenant and d.generation_id=generation and d.fact_id=f.fact_id;
 get diagnostics displayed=row_count;
 update private.hub_trading_destination_audit_v1 x set after_record=to_jsonb(f)
 from private.hub_kpi_prepared_facts f where x.operation_id=operation
 and x.record_kind='prepared_fact' and x.record_key=f.fact_id
 and f.tenant_id=tenant and f.generation_id=generation;
 if corrected<>displayed or corrected<>(select count(*) from private.hub_trading_destination_audit_v1
  where operation_id=operation and record_kind='prepared_fact') or exists(
  select 1 from private.hub_trading_destination_audit_v1 x where x.operation_id=operation
  and x.record_kind='prepared_fact' and (x.before_record->'amount' is distinct from x.after_record->'amount'
   or x.before_record->'occurred_on' is distinct from x.after_record->'occurred_on'
   or x.before_record->'cost_center' is distinct from x.after_record->'cost_center')) then
  raise exception 'Trading correction conservation check failed';end if;
 update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=tenant;
end $$;
