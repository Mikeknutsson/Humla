-- Monetary source priority is an automatic decision, not a manual review gate.
-- Keep discrepancies visible without blocking or changing published amounts.
create or replace view private.hub_stena_price_review_v1 with(security_invoker=true) as
with workify as materialized (
 select a.tenant_id,a.portal_ids[1] object_id,
 sum((a.before_fact->>'amount')::numeric) workify_amount,count(*) workify_rows
 from private.hub_stena_projection_audit_v1 a
 join private.hub_kpi_report_state s on s.tenant_id=a.tenant_id and s.active_generation=a.generation_id
 where cardinality(a.portal_ids)=1
 group by a.tenant_id,a.portal_ids[1]
), differences as (
 select r.tenant_id,r.revenue_object_id,r.booking,r.occurred_on,r.registration,
 f.file_name,r.row_number,r.price,r.extra,r.load_count,
 coalesce(o.amount,r.amount) stena_amount,w.workify_amount,w.workify_rows,
 w.workify_amount-coalesce(o.amount,r.amount) difference
 from private.hub_stena_rows_v1 r join private.hub_stena_files_v1 f using(tenant_id,file_hash)
 join workify w on w.tenant_id=r.tenant_id and w.object_id=r.revenue_object_id
 left join private.hub_stena_amount_overrides_v1 o on o.tenant_id=r.tenant_id and o.revenue_object_id=r.revenue_object_id
 where f.source_kind='history' and o.revenue_object_id is null
 and abs(w.workify_amount-r.amount)>=1
)
select d.*,
 case when d.stena_amount=0 and not exists (
 select 1 from private.hub_kpi_prepared_facts f join private.hub_kpi_report_state s
 on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
 where f.tenant_id=d.tenant_id and f.fact_id=d.revenue_object_id::text and f.amount<>0)
 then 'automatically_applied_stena_zero'
 when exists (
 select 1 from private.hub_kpi_prepared_facts f join private.hub_kpi_report_state s
 on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
 where f.tenant_id=d.tenant_id and f.fact_id=d.revenue_object_id::text and f.amount=d.stena_amount)
 then 'automatically_applied_stena_amount'
 else 'awaiting_report_refresh' end::text status,
 false blocking,
 d.stena_amount selected_amount,
 'Stena history row total; Workify difference retained for information'::text resolution_rule,
 case when d.stena_amount=0 then 'stena_explicit_zero'
 when d.workify_rows>1 then 'multiple_workify_lines'
 when d.load_count>1 and abs(d.workify_amount-(d.price+coalesce(d.extra,0))*d.load_count)<1 then 'workify_matches_load_multiplier'
 when d.load_count>1 and abs(d.workify_amount-d.price*d.load_count-coalesce(d.extra,0))<1 then 'workify_matches_multiplier_extra_once'
 when abs(d.difference)<=1 then 'rounding_difference'
 else 'source_amount_difference' end::text difference_reason
from differences d;
revoke all on private.hub_stena_price_review_v1 from public,anon,authenticated;

do $verify$
begin
 if exists(select 1 from private.hub_stena_price_review_v1 where blocking)
 then raise exception 'Price discrepancy must not block reporting';end if;
 if exists(select 1 from private.hub_stena_price_review_v1 where selected_amount is distinct from stena_amount)
 then raise exception 'Source selection mismatch';end if;
end $verify$;
