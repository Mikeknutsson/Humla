-- Run as database owner with request.jwt.claim.sub and test.tenant_id set.
-- Checks published allocations; rolls back the idempotence probe.
begin;
do $$
declare tenant uuid:=current_setting('test.tenant_id')::uuid; generation uuid;
begin
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=tenant;
 if not exists(select 1 from private.hub_cost_allocation_applied_v1 where tenant_id=tenant and generation_id=generation) then raise exception 'No allocation fixture';end if;
 if exists(
 select 1 from private.hub_cost_allocation_applied_v1 a left join (
 select original#>>'{_humla_cost_rule,original_fact_id}' original_id,sum(amount) amount
 from private.hub_kpi_prepared_display_facts where tenant_id=tenant and generation_id=generation group by 1
 ) f on f.original_id=a.original_fact_id
 where a.tenant_id=tenant and a.generation_id=generation and f.amount is distinct from (a.before_fact->>'amount')::numeric
 ) then raise exception 'Source amount not conserved';end if;
 if exists(select 1 from private.hub_kpi_prepared_display_facts f where f.tenant_id=tenant and f.generation_id=generation and f.original#>>'{_humla_cost_rule,status}'='allocated' and not exists(
 select 1 from public.hub_objects o cross join lateral jsonb_array_elements(o.data->'periods') p
 where o.tenant_id=tenant and o.object_type='EconomicUnit' and o.id=f.unit_id and (p.value->>'enabled')::boolean
 and (p.value->>'valid_from')::date<=f.occurred_on and ((p.value->>'valid_to') is null or (p.value->>'valid_to')::date>=f.occurred_on)
 )) then raise exception 'Recipient not active on transaction date';end if;
end $$;
do $$declare repeated jsonb;tenant uuid:=current_setting('test.tenant_id')::uuid;begin
 repeated:=private.hub_apply_cost_allocation_v1(tenant,(select active_generation from private.hub_kpi_report_state where tenant_id=tenant));
 if (repeated->>'source_rows')::int<>0 then raise exception 'Repeated run changed facts';end if;
end $$;
rollback;
