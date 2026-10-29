begin;set local jit=off;select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $test$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';g uuid;r jsonb;n int;
begin
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 r:=private.hub_resolve_pending_material_prices_v1(t,g,array['942a54e7-2e60-4316-ac5d-882dad557372'::uuid,'124e6c90-467d-48be-b935-37dae5021866'::uuid]);
 assert (r->>'split_rows')::int=0,'Replay must be idempotent';
 select count(*) into n from private.hub_kpi_prepared_facts f where f.tenant_id=t and f.generation_id=g and f.fact_id in('942a54e7-2e60-4316-ac5d-882dad557372','124e6c90-467d-48be-b935-37dae5021866') and (f.category<>'transport' or f.original#>>'{_humla_material_separation,component}'<>'transport' or (f.original#>>'{_humla_material_separation,purchase,price_sample_count}'<>'3' and not coalesce((f.original#>>'{_humla_material_separation,purchase,standard_project_fallback}')::boolean,false)));
 assert n=0,'Transport remainder and three-price or owner-approved Kylinge evidence missing';
 assert (select sum(amount) from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and fact_id in('942a54e7-2e60-4316-ac5d-882dad557372','124e6c90-467d-48be-b935-37dae5021866','942a54e7-2e60-4316-ac5d-882dad557372:material','124e6c90-467d-48be-b935-37dae5021866:material'))=19596.21,'Split sum changed';
 assert (select sum(amount) from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and fact_id in('942a54e7-2e60-4316-ac5d-882dad557372:material','124e6c90-467d-48be-b935-37dae5021866:material'))=13807.01,'Material portion incorrect';
 assert (select unit_id from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and fact_id='ee74482f-0c09-4ba2-a569-3de8aaca2c24')='c59071d8-91b4-4668-9a4e-ec8ae761c86d'::uuid,'Explicit material-only source comment not routed';
 select count(*) into n from private.hub_kpi_prepared_facts f join private.hub_kpi_prepared_display_facts d using(tenant_id,generation_id,fact_id) where f.tenant_id=t and f.generation_id=g and f.fact_id in('ee74482f-0c09-4ba2-a569-3de8aaca2c24','942a54e7-2e60-4316-ac5d-882dad557372','124e6c90-467d-48be-b935-37dae5021866','942a54e7-2e60-4316-ac5d-882dad557372:material','124e6c90-467d-48be-b935-37dae5021866:material') and row(f.amount,f.unit_id,f.category,f.vehicle) is distinct from row(d.amount,d.unit_id,d.category,d.vehicle);
 assert n=0,'Published display mismatch';
end $test$;
select 'PASS: idempotent split, three-price evidence, pair totals, material-only comment, published display' verification;
rollback;