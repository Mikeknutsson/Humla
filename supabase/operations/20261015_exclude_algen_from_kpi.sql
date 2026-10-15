begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
insert into private.hub_kpi_project_exclusions(tenant_id,project_id,economic_unit_id,display_name,reason,approved_by)
values('944597b6-9c46-4bef-998d-f19e23c4245b','d0e501bc-b300-479e-8941-e9227b635113','aeba8527-8d13-41e0-9d72-049b75d89555',
 'Rivning Kv Älgen','Användarbeslut 2026-10-15: backa intäktskopplingen och håll rivningen utanför KPI-uppföljningen tills avstämning är klar.',auth.uid())
on conflict(tenant_id,project_id)do update set enabled=true,reason=excluded.reason,approved_by=excluded.approved_by,approved_at=now();
-- Reverse only the derived assignment of the exact Workify invoice, not the invoice.
update private.hub_kpi_prepared_facts f set
 project=a.before_record->>'project',unit_id=nullif(a.before_record->>'unit_id','')::uuid,unit_name=null,
 vehicle=a.before_record->>'vehicle',cost_center=a.before_record->>'cost_center',cost_center_name='Ej klassificerat',business_group=a.before_record->>'business_group',
 classification_source=coalesce(f.classification_source,'{}')||jsonb_build_object('remaining_unit_resolution','rolled_back_pending_scope'),
 display_original=f.display_original||jsonb_build_object('_humla_unit_resolution','rolled_back_pending_scope')
from private.hub_remaining_unit_routing_audit a,private.hub_kpi_report_state s
where f.tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b' and s.tenant_id=f.tenant_id and f.generation_id=s.active_generation
and a.generation_id=f.generation_id and a.fact_id=f.fact_id and a.tenant_id=f.tenant_id and f.fact_id='7dbeb616-40fc-4ff8-aa4c-de80526a70d3'
and f.classification_source->>'remaining_unit_resolution'='confirmed_dated_membership';
update private.hub_kpi_prepared_display_facts d set project=f.project,unit_id=f.unit_id,unit_name=f.unit_name,vehicle=f.vehicle,cost_center=f.cost_center,business_group=f.business_group,original=f.display_original
from private.hub_kpi_prepared_facts f,private.hub_kpi_report_state s where f.tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b'and s.tenant_id=f.tenant_id and f.generation_id=s.active_generation
and f.fact_id='7dbeb616-40fc-4ff8-aa4c-de80526a70d3'and d.tenant_id=f.tenant_id and d.generation_id=f.generation_id and d.fact_id=f.fact_id;
select private.hub_kpi_publish_project_exclusions_v1(tenant_id,active_generation)excluded_rows from private.hub_kpi_report_state where tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b';
update private.hub_kpi_report_state set correction_revision=coalesce(correction_revision,0)+1 where tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b';
commit;
