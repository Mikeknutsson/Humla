create or replace view public.hub_kpi_probabilistic_vehicle_candidates_v1 with (security_invoker=true) as
with evidence as (
select r.id transaction_id,r.tenant_id,r.occurred_on,r.vehicle_registration,
m.id rule_id,m.target_value candidate_vehicle,m.evidence_type,
case m.evidence_type
 when 'vehicle_registration' then 100
 when 'driver' then 45
 when 'project' then 30
 when 'supervisor' then 20
 when 'customer' then 15
 when 'reference' then 15
 when 'article' then 10
 when 'account' then 8
 when 'supplier' then 8
 else 5 end * m.confidence as evidence_score
from public.kpi_import_rows r
join public.hub_allocation_mapping_rules m on m.tenant_id=r.tenant_id
 and m.dimension='vehicle' and m.rule_status='confirmed'
 and (m.valid_from is null or r.occurred_on>=m.valid_from)
 and (m.valid_to is null or r.occurred_on<=m.valid_to)
 and upper(trim(m.evidence_value))=upper(trim(case m.evidence_type
 when 'project' then r.project_reference
 when 'account' then r.account
 when 'vehicle_registration' then r.vehicle_registration
 when 'driver' then r.employee_number
 when 'reference' then r.description
 when 'supervisor' then r.source_data->>'supervisor'
 when 'customer' then r.source_data->>'customer'
 when 'supplier' then r.source_data->>'supplier'
 when 'article' then r.source_data->>'article'
 else null end))
where r.vehicle_registration is null and r.occurred_on is not null
), scored as (
select transaction_id,tenant_id,occurred_on,candidate_vehicle,
least(100,round(sum(evidence_score),1)) confidence_score,
count(distinct evidence_type) independent_evidence_types,
count(*) matching_rules
from evidence group by 1,2,3,4
), ranked as (
select scored.*,row_number() over(partition by transaction_id order by confidence_score desc,independent_evidence_types desc,candidate_vehicle) candidate_rank,
lead(confidence_score) over(partition by transaction_id order by confidence_score desc,independent_evidence_types desc,candidate_vehicle) next_score
from scored)
select *,case
 when candidate_rank<>1 then 'alternative'
 when confidence_score>=85 and independent_evidence_types>=2 and (next_score is null or confidence_score-next_score>=20) then 'high_confidence_proposal'
 when confidence_score>=50 and (next_score is null or confidence_score-next_score>=15) then 'review_proposal'
 else 'insufficient_or_conflicting_evidence' end decision
from ranked;
