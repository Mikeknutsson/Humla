begin;set local jit=off;select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $test$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';g uuid;p jsonb;r jsonb;n int;
begin
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 p:=private.hub_kpi_material_purchase_costs_v1(t,array['94b9eaa6-6519-4e3e-bcdc-1e0b930199ac'::uuid,'42932d67-bc31-4457-b23c-e1f6467d7ee1'::uuid,'2455a01e-814d-45a2-8dd1-fc693ab0e97b'::uuid]);
 assert (p#>>'{94b9eaa6-6519-4e3e-bcdc-1e0b930199ac,rate}')::numeric=65,'Existing project price must win';
 assert (p#>>'{42932d67-bc31-4457-b23c-e1f6467d7ee1,rate}')::numeric=121.5,'Valid August Kylinge standard price must be used';
 assert (p#>>'{42932d67-bc31-4457-b23c-e1f6467d7ee1,standard_project_fallback}')::boolean,'Fallback must be explicit';
 assert p#>'{2455a01e-814d-45a2-8dd1-fc693ab0e97b,rate}'='null'::jsonb,'Expired August prices must not leak into October';
 select count(*) into n from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and source='Workify' and kind='revenue' and occurred_on>='2025-09-01' and description ilike '%Fyllnadsmaterial%' and(unit_id is distinct from '99c80bd8-c2ce-47f3-b4a8-8d1fa1010940'::uuid or cost_center<>'20');
 assert n=0,'Fill revenue must be in Schakt KST20';
 r:=private.hub_detach_vehicle_nontransport_v1(t,g);
 assert(r->>'changed_rows')::int=0,'Routing must be idempotent';
 r:=private.hub_reprice_standard_material_pairs_v1(t,g,array['23f95a8c-1d4c-4a38-9f10-3072c62c0439'::uuid,'65ff52a2-1c82-482a-8345-a4e08077af80'::uuid,'942a54e7-2e60-4316-ac5d-882dad557372'::uuid,'c005241e-ccd8-49b6-b902-b6dd58d8f01d'::uuid,'d39fb93b-8387-4a83-905a-e5437f64ffc2'::uuid,'e7060e22-1f5e-4f91-9ecb-9f97b5a86277'::uuid]);
 assert(r->>'repriced_pairs')::int=0,'Repricing must be idempotent';
 select count(*) into n from private.hub_kpi_prepared_facts f left join private.hub_kpi_prepared_display_facts d using(tenant_id,generation_id,fact_id)
 where f.tenant_id=t and f.generation_id=g and(f.original?'_humla_material_reprice' or f.original#>>'{_humla_vehicle_component_correction,rule}'='fill_material')
 and(d.fact_id is null or row(f.amount,f.unit_id,f.category,f.cost_center) is distinct from row(d.amount,d.unit_id,d.category,d.cost_center));
 assert n=0,'Live display differs from backend';
end $test$;
select 'PASS: project priority, standard fallback, validity dates, canonical Schakt KST20 destination, idempotence and live display' verification;
rollback;