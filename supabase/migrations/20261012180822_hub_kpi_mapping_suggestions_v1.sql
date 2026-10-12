create or replace view public.hub_kpi_mapping_suggestions_v1 with (security_invoker=true) as
select r.id as transaction_id,r.tenant_id,r.batch_id,r.occurred_on,r.data_kind,r.amount,
m.id as rule_id,m.dimension,m.evidence_type,m.evidence_value,m.target_value,m.confidence,
case when m.confidence=1 then 'confirmed_rule' else 'suggested_rule' end as match_status
from public.kpi_import_rows r
join public.hub_allocation_mapping_rules m on m.tenant_id=r.tenant_id and m.rule_status='confirmed'
and (m.valid_from is null or r.occurred_on>=m.valid_from)
and (m.valid_to is null or r.occurred_on<=m.valid_to)
and upper(trim(m.evidence_value))=upper(trim(case m.evidence_type
when 'project' then r.project_reference
when 'account' then r.account
when 'vehicle_registration' then r.vehicle_registration
when 'reference' then r.description
when 'driver' then r.employee_number
else null end))
where (m.dimension='vehicle' and r.vehicle_registration is null)
or (m.dimension='cost_center' and r.cost_center is null)
or (m.dimension='project' and r.project_reference is null);
