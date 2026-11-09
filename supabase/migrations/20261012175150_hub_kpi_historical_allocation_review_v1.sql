create or replace view public.hub_kpi_historical_allocation_review_v1 with (security_invoker = true) as
select r.id,r.tenant_id,r.batch_id,r.occurred_on,r.amount,r.project_reference,r.cost_center,r.vehicle_registration,r.account,r.source_fingerprint,
case when r.data_kind='cost' and r.is_valid=false and r.validation_errors='["Kostnadsfördelning behöver granskas"]'::jsonb then 'allocation_only_legacy' when r.is_valid then 'currently_valid' else 'other_validation' end as review_category,
case when r.data_kind='cost' and r.is_valid=false and r.validation_errors='["Kostnadsfördelning behöver granskas"]'::jsonb then 'unallocated' else coalesce(r.allocation->>'allocation_status','unknown') end as allocation_status
from public.kpi_import_rows r
where r.data_kind='cost';
