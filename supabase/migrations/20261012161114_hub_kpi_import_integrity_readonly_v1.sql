create or replace view public.hub_kpi_import_integrity_v1 with (security_invoker=true) as
with base as (
 select r.tenant_id,r.data_kind,r.id,r.batch_id,r.occurred_on,r.amount,r.is_valid,r.cost_center,
 md5(r.source_data::text) as payload_hash,
 count(*) over(partition by r.tenant_id,r.data_kind,md5(r.source_data::text)) as identical_count,
 min(r.batch_id::text) over(partition by r.tenant_id,r.data_kind,md5(r.source_data::text)) as first_batch
 from public.kpi_import_rows r
)
select tenant_id,data_kind,count(*) as imported_rows,
 count(*) filter(where not is_valid) as invalid_rows,
 count(*) filter(where identical_count>1) as rows_in_repeated_payloads,
 count(*) filter(where identical_count>1 and batch_id::text<>first_batch) as cross_batch_repeat_candidates,
 count(*) filter(where cost_center is null or btrim(cost_center)='') as missing_cost_center,
 sum(amount) filter(where not is_valid) as invalid_amount
from base group by tenant_id,data_kind;
revoke all on public.hub_kpi_import_integrity_v1 from anon;
grant select on public.hub_kpi_import_integrity_v1 to authenticated;
