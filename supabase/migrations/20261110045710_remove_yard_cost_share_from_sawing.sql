select pg_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0));

create or replace function private.hub_apply_yard_saw_share_v1(p_tenant uuid, p_generation uuid)
returns jsonb
language sql
set search_path to ''
as $function$
  select jsonb_build_object('source_rows', 0, 'transferred', 0);
$function$;

do $backfill$
declare
  report record;
  pair_count bigint;
  changed_count bigint;
begin
  for report in
    select s.tenant_id, s.active_generation, r.unit_id as saw_unit
    from private.hub_kpi_report_state s
    join private.hub_saw_activity_rules_v1 r on r.tenant_id=s.tenant_id
    where s.active_generation is not null
    for update of s
  loop
    perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||report.tenant_id::text,0));

    select count(*) into pair_count
    from private.hub_kpi_prepared_facts f
    where f.tenant_id=report.tenant_id and f.generation_id=report.active_generation
      and f.original?'_humla_yard_saw_share';

    if pair_count=0 then continue; end if;

    if exists (
      select 1 from private.hub_kpi_prepared_facts f
      where f.tenant_id=report.tenant_id and f.generation_id=report.active_generation
        and f.original?'_humla_yard_saw_share'
      group by f.original#>>'{_humla_yard_saw_share,original_fact_id}'
      having count(*)<>2
        or count(*) filter (where f.original#>>'{_humla_yard_saw_share,branch}'='yard'
          and f.cost_center='20' and f.kind='cost' and f.fact_id=f.original#>>'{_humla_yard_saw_share,original_fact_id}')<>1
        or count(*) filter (where f.original#>>'{_humla_yard_saw_share,branch}'='saw'
          and f.unit_id=report.saw_unit and f.kind='cost')<>1
        or sum(f.amount) is distinct from max((f.original#>>'{_humla_yard_saw_share,original_amount}')::numeric)
    ) then raise exception 'Invalid Yard/Saw cost pairs'; end if;

    update private.hub_kpi_prepared_facts f
    set amount=(f.original#>>'{_humla_yard_saw_share,original_amount}')::numeric,
        original=f.original-'_humla_yard_saw_share',
        display_original=f.display_original-'_humla_yard_saw_share'
    where f.tenant_id=report.tenant_id and f.generation_id=report.active_generation
      and f.original#>>'{_humla_yard_saw_share,branch}'='yard';

    update private.hub_kpi_prepared_display_facts d
    set amount=f.amount, original=f.display_original
    from private.hub_kpi_prepared_facts f
    where d.tenant_id=report.tenant_id and d.generation_id=report.active_generation
      and d.original#>>'{_humla_yard_saw_share,branch}'='yard'
      and (f.tenant_id,f.generation_id,f.fact_id)=(d.tenant_id,d.generation_id,d.fact_id);
    get diagnostics changed_count=row_count;
    if changed_count*2<>pair_count then raise exception 'Incomplete Yard display restoration'; end if;

    delete from private.hub_kpi_prepared_display_facts d
    using private.hub_kpi_prepared_facts f
    where f.tenant_id=report.tenant_id and f.generation_id=report.active_generation
      and f.original#>>'{_humla_yard_saw_share,branch}'='saw'
      and (d.tenant_id,d.generation_id,d.fact_id)=(f.tenant_id,f.generation_id,f.fact_id);
    get diagnostics changed_count=row_count;
    if changed_count*2<>pair_count then raise exception 'Incomplete Saw display reversal'; end if;

    delete from private.hub_kpi_prepared_facts f
    where f.tenant_id=report.tenant_id and f.generation_id=report.active_generation
      and f.original#>>'{_humla_yard_saw_share,branch}'='saw';

    perform private.hub_validate_report_projection_v1(report.tenant_id,report.active_generation);
    update private.hub_kpi_report_state
    set correction_revision=correction_revision+1
    where tenant_id=report.tenant_id;
  end loop;
end;
$backfill$;
