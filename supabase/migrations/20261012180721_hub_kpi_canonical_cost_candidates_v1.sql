create or replace view public.hub_kpi_canonical_cost_candidates_v1 with (security_invoker=true) as
with ranked as (
select o.*, b.created_at as imported_at,
row_number() over(partition by o.tenant_id,o.source_content_hash,o.occurrence_in_batch order by b.created_at,o.batch_id,o.row_number,o.id) as candidate_rank
from public.hub_kpi_historical_source_occurrences_v1 o
join public.kpi_import_batches b on b.id=o.batch_id and b.tenant_id=o.tenant_id
)
select id,tenant_id,batch_id,row_number,occurred_on,amount,project_reference,cost_center,source_content_hash,occurrence_in_batch,copies_in_batch,batches_with_same_content,imported_at,candidate_rank,
case when candidate_rank=1 then 'candidate_primary' else 'candidate_overlap' end as dedup_review_status
from ranked;
