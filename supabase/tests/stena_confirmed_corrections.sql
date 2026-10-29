begin;set local jit=off;select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $test$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';g uuid;b numeric;a numeric;
begin
select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
select sum(amount)into b from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g;
perform private.hub_apply_stena_priority_v1(t,g);
select sum(amount)into a from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g;
assert a=b,'Replay changes financial totals';
assert(select amount from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and original#>>'{_humla_stena_portal,booking}'='76763146')=19330,'Confirmed single maskinflytt amount missing';
assert not exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and source='Stena portal'and original->>'RegNr'='GJJT66B'and(vehicle<>'GJT66B'or unit_id<>'3fa521ea-e36e-458b-867d-1eff4797420b')),'Confirmed alias not routed';
assert not exists(select fact_id from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and source='Stena portal'group by fact_id having count(*)>1),'Duplicate portal facts';
assert not exists(select 1 from private.hub_kpi_prepared_facts f left join private.hub_kpi_prepared_display_facts d using(tenant_id,generation_id,fact_id)where f.tenant_id=t and f.generation_id=g and f.source='Stena portal'and row(f.amount,f.unit_id,f.vehicle)is distinct from row(d.amount,d.unit_id,d.vehicle)),'Display differs';
end $test$;
select 'PASS: exact owner amount, canonical alias, replay, duplicate protection and display' verification;
rollback;