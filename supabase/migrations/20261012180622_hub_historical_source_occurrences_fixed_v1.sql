create or replace view public.hub_kpi_historical_source_occurrences_v1 with (security_invoker=true) as
with base as (select r.id,r.tenant_id,r.batch_id,r.row_number,r.occurred_on,r.amount,r.project_reference,r.cost_center,r.source_fingerprint,r.data_kind,md5(r.source_data::text) as source_content_hash from public.kpi_import_rows r where r.data_kind='cost'),
counts as (select tenant_id,data_kind,source_content_hash,count(distinct batch_id) batches_with_same_content from base group by 1,2,3)
select b.id,b.tenant_id,b.batch_id,b.row_number,b.occurred_on,b.amount,b.project_reference,b.cost_center,b.source_fingerprint,b.source_content_hash,
row_number() over(partition by b.tenant_id,b.data_kind,b.source_content_hash,b.batch_id order by b.row_number,b.id) as occurrence_in_batch,
count(*) over(partition by b.tenant_id,b.data_kind,b.source_content_hash,b.batch_id) as copies_in_batch,c.batches_with_same_content
from base b join counts c using(tenant_id,data_kind,source_content_hash);
