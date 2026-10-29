begin;set local jit=off;set local statement_timeout='20s';
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $test$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';yard uuid:='591d7698-bea7-46ce-a994-ddcb8d943500';ola uuid:='7f87dae3-7055-473d-89e5-849905a65846';r jsonb;h numeric;sep jsonb;oct jsonb;
begin
r:=public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29',yard);
assert(r#>>'{area_kpis,worked_hours}')::numeric=250,'Approved yard NEXT hours missing';
assert r#>>'{area_kpis,time_to}'='2026-09-30','Finance must stop at matching time cutoff';
assert abs((r#>>'{area_kpis,revenue_per_hour}')::numeric*250-(r#>>'{area_kpis,time_revenue}')::numeric)<0.0001,'Revenue denominator mismatch';
assert abs((r#>>'{area_kpis,cost_per_hour}')::numeric*250-(r#>>'{area_kpis,time_cost}')::numeric)<0.0001,'Cost denominator mismatch';
assert abs((r#>>'{area_kpis,result_per_hour}')::numeric-((r#>>'{area_kpis,revenue_per_hour}')::numeric-(r#>>'{area_kpis,cost_per_hour}')::numeric))<0.0001,'Result ratio mismatch';
sep:=public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29',yard,null,0,array[9]);
oct:=public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29',yard,null,0,array[10]);
assert(sep#>>'{area_kpis,worked_hours}')::numeric=250,'Month filter lost September hours';
assert oct#>>'{area_kpis,worked_hours}'is null,'October hours fabricated';
r:=public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29',ola);
assert(r#>>'{area_kpis,worked_hours}')::numeric>5000,'Existing verified TransPA suppressed by non-time personnel rows';
perform set_config('request.jwt.claim.sub',yard::text,true);
r:=public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29',yard);
assert(r#>>'{area_kpis,worked_hours}')::numeric=250,'Supervisor cannot read own time KPI';
begin
perform public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29',ola);
raise exception 'Cross-profile access permitted';
exception when insufficient_privilege then null;end;
perform set_config('request.jwt.claim.sub','',true);
begin
perform public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29',yard);
raise exception 'Anonymous access permitted';
exception when insufficient_privilege or invalid_parameter_value then null;end;
end $test$;
select 'PASS: NEXT and TransPA totals, date/month scope, matched finance period, arithmetic, own-profile access, cross-profile and anonymous denial' verification;
rollback;