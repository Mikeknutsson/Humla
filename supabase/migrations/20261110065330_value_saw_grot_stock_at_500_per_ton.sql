select pg_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0));

do $change$
declare
  rule record;
  generation uuid;
  changed_rows bigint;
begin
  for rule in
    update private.hub_saw_activity_rules_v1
    set chip_rate_per_ton=500
    where chip_rate_per_ton=600
    returning tenant_id,unit_id
  loop
    select active_generation into generation
    from private.hub_kpi_report_state
    where tenant_id=rule.tenant_id
    for update;

    perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||rule.tenant_id::text,0));

    with repriced as (
      update private.hub_kpi_prepared_facts f
      set amount=round((f.original#>>'{_humla_saw_chip,tons}')::numeric*500,2),
          original=jsonb_set(f.original,'{_humla_saw_chip,rate_per_ton}','500'),
          display_original=jsonb_set(f.display_original,'{_humla_saw_chip,rate_per_ton}','500')
      where f.tenant_id=rule.tenant_id and f.generation_id=generation and f.unit_id=rule.unit_id
        and f.kind='revenue' and f.original?'_humla_saw_chip'
      returning f.tenant_id,f.generation_id,f.fact_id,f.amount,f.display_original
    )
    update private.hub_kpi_prepared_display_facts d
    set amount=f.amount, original=f.display_original
    from repriced f
    where (d.tenant_id,d.generation_id,d.fact_id)=(f.tenant_id,f.generation_id,f.fact_id);

    get diagnostics changed_rows=row_count;
    if changed_rows>0 then
      perform private.hub_validate_report_projection_v1(rule.tenant_id,generation);
      update private.hub_kpi_report_state set correction_revision=correction_revision+1
      where tenant_id=rule.tenant_id;
    end if;
  end loop;
end;
$change$;