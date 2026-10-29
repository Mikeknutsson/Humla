begin;set local jit=off;select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $test$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';g uuid;b numeric;a numeric;
begin
select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
select sum(amount)into b from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g;
perform private.hub_apply_saw_activity_v1(t,g);
select sum(amount)into a from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g;
assert a=b,'Replay changed total costs';
assert not exists(select original#>>'{_humla_saw_activity,original_fact_id}' from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and original#>>'{_humla_saw_activity,reason}'='supplier_work_full'group by 1 having abs(sum(amount)-max((original#>>'{_humla_saw_activity,original_amount}')::numeric))>0.00001),'Source invoice no longer conserves';
assert not exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and original#>>'{_humla_saw_activity,reason}'='supplier_work_full'and original#>>'{_humla_saw_activity,branch}'='saw'and amount<>round((original#>>'{_humla_saw_activity,original_amount}')::numeric*0.5,2)),'Direct saw share incorrect';
assert not exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and original#>>'{_humla_saw_activity,reason}'='supplier_work_full'and original#>>'{_humla_saw_activity,branch}'='retained'and(cost_center<>'10'or amount<>round((original#>>'{_humla_saw_activity,original_amount}')::numeric*0.25,2))),'Enterprise share incorrect';
assert not exists(select 1 from private.hub_kpi_prepared_facts f left join private.hub_kpi_prepared_display_facts d using(tenant_id,generation_id,fact_id)where f.tenant_id=t and f.generation_id=g and f.original#>>'{_humla_saw_activity,reason}'='supplier_work_full'and row(f.amount,f.unit_id,f.cost_center)is distinct from row(d.amount,d.unit_id,d.cost_center)),'Display mismatch';
end $test$;
select 'PASS: source conservation, replay, direct 50 percent, enterprise 25 percent and display' verification;
rollback;