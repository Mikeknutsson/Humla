-- Run with a trusted database operator. All test mutations are rolled back.
begin;set local jit=off;set local statement_timeout='25s';
do $test$
declare cfg private.hub_stena_rules_v1;g uuid;before_sum numeric;after_sum numeric;result jsonb; n int;
begin
for cfg in select * from private.hub_stena_rules_v1 where enabled loop
perform set_config('request.jwt.claim.sub',cfg.approved_by::text,true);
select active_generation into g from private.hub_kpi_report_state where tenant_id=cfg.tenant_id;
select sum(amount)into before_sum from private.hub_kpi_prepared_facts where tenant_id=cfg.tenant_id and generation_id=g;
result:=private.hub_apply_stena_priority_v1(cfg.tenant_id,g);
select sum(amount)into after_sum from private.hub_kpi_prepared_facts where tenant_id=cfg.tenant_id and generation_id=g;
assert before_sum=after_sum,'Replay changes financial total';
assert not exists(select 1 from private.hub_stena_projection_audit_v1 a join private.hub_kpi_prepared_facts f using(tenant_id,generation_id,fact_id)where a.tenant_id=cfg.tenant_id and a.generation_id=g),'Superseded Workify still counted';
assert not exists(select fact_id from private.hub_kpi_prepared_facts where tenant_id=cfg.tenant_id and generation_id=g and source='Stena portal'group by fact_id having count(*)<>1),'Duplicate portal journey';
assert not exists(select 1 from private.hub_kpi_prepared_facts f left join private.hub_kpi_prepared_display_facts d using(tenant_id,generation_id,fact_id)where f.tenant_id=cfg.tenant_id and f.generation_id=g and f.source='Stena portal'and(d.fact_id is null or row(f.amount,f.unit_id,f.cost_center)is distinct from row(d.amount,d.unit_id,d.cost_center))),'Display differs';
assert not exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=cfg.tenant_id and generation_id=g and original#>>'{_humla_stena_portal,fallback}'='true'and unit_id<>cfg.fallback_unit_id),'Fallback unit wrong';
perform set_config('request.jwt.claim.sub','',true);
begin
perform private.hub_apply_stena_priority_v1(cfg.tenant_id,g);
raise exception 'Anonymous projection permitted';
exception when insufficient_privilege then null;end;
end loop;
end $test$;
select 'PASS: replay conservation, no duplicates, priority exclusion, display equality, fallback and authorization' verification;
rollback;