begin;set local jit=off;select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $test$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';u uuid:='bc566ca4-dc80-4d81-a7dc-1378eec7bb93';r jsonb;g uuid;b numeric;a numeric;
begin
select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
select sum(amount)into b from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g;
r:=public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29',u);
assert(r#>>'{area_kpis,worked_hours}')::numeric>0,'Saw time still missing';
assert(r#>>'{area_kpis,time_sources,shared_crane_time}')::boolean,'Shared source must be explicit';
assert(r#>>'{area_kpis,covered_units}')::int=1,'Saw time must be linked to canonical saw unit';
assert(r#>>'{area_kpis,revenue_per_hour}')::numeric is not null,'Saw hourly KPI missing';
select sum(amount)into a from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g;
assert a=b,'Time presentation changed financial totals';
perform set_config('request.jwt.claim.sub',u::text,true);
r:=public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29',u);
assert(r#>>'{area_kpis,worked_hours}')::numeric>0,'Own supervisor saw scope failed';
begin
perform public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29','7f87dae3-7055-473d-89e5-849905a65846');
raise exception 'Cross-profile permission widened';
exception when insufficient_privilege then null;end;
end $test$;
select 'PASS: shared saw work time, canonical scope, hourly KPI, unchanged finances and supervisor isolation' verification;
rollback;