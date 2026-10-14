-- Export approval and financial source validity are independent controls.
-- Retain historical export rows; never reactivate withdrawn imports by approval.
create function private.hub_repair_financial_scope_v1(p_tenant uuid,p_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare generation uuid;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read') then raise exception 'Behörighet saknas';end if;
 if p_ids is null or cardinality(p_ids)>2000 then raise exception 'Invalid repair selection';end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant;
 with requested as materialized(
 select o.*,r.id row_exists,r.amount source_amount,r.occurred_on source_date,r.account source_account,
 b.status batch_status,coalesce(b.provenance,'{}')?'withdrawal' withdrawn
 from public.hub_fordonskontrollen_cost_outbox o
 left join public.kpi_import_rows r on r.id=o.source_row_id and r.tenant_id=o.tenant_id
 left join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 where o.tenant_id=p_tenant and o.id=any(p_ids)
 ),sources as materialized(
 select split_part(f.fact_id,':',1)row_id,f.occurred_on,f.account,sum(f.amount)amount
 from private.hub_kpi_prepared_facts f where f.generation_id=generation and f.tenant_id=p_tenant and f.source='NEXT' and f.kind='cost'
 and f.occurred_on between(select min(occurred_on)from requested)and(select max(occurred_on)from requested)
 group by 1,2,3
 ),states as(
 select r.id,case when r.row_exists is null then 'missing_source'
 when r.withdrawn then 'withdrawn_import'
 when r.batch_status not in('completed','needs_review') or r.batch_status is null then 'inactive_import'
 when s.row_id is null then 'not_in_published_scope'
 when row(r.source_amount,r.source_date,r.source_account) is distinct from row(r.amount,r.occurred_on,r.account)
 or s.amount is distinct from r.amount then 'changed_source'
 else 'active' end reason
 from requested r left join sources s on s.row_id=r.source_row_id::text and s.occurred_on=r.occurred_on and s.account=r.account
 )select coalesce(jsonb_agg(jsonb_build_object('id',id,'published',reason='active','reason',reason)order by id),'[]'::jsonb)into answer from states;
 return answer;
end $$;
revoke all on function private.hub_repair_financial_scope_v1(uuid,uuid[]) from public,anon;
grant execute on function private.hub_repair_financial_scope_v1(uuid,uuid[]) to authenticated,service_role;
create function public.hub_repair_financial_scope_v1(p_tenant uuid,p_ids uuid[])
returns jsonb language sql stable security invoker set search_path='' as $$select private.hub_repair_financial_scope_v1(p_tenant,p_ids)$$;
revoke all on function public.hub_repair_financial_scope_v1(uuid,uuid[]) from public,anon;
grant execute on function public.hub_repair_financial_scope_v1(uuid,uuid[]) to authenticated,service_role;
