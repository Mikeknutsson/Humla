begin;
set local jit=off;
set local statement_timeout='25s';
do $tests$ begin
if private.hub_driver_goal_deviation_v1(10000,9200,1000,0)<>-20 then raise exception '8 percent versus 10 percent goal must be 20 percent below';end if;
if private.hub_driver_goal_deviation_v1(10000,8800,1000,0)<>20 then raise exception '12 percent versus 10 percent goal must be 20 percent above';end if;
if private.hub_driver_goal_deviation_v1(10000,9000,1000,0)<>0 then raise exception 'On target';end if;
if private.hub_driver_goal_deviation_v1(0,1,1,0) is not null or private.hub_driver_goal_deviation_v1(10000,9000,0,0)is not null or private.hub_driver_goal_deviation_v1(10000,9000,1000,1)is not null then raise exception 'Missing or zero target must remain unknown';end if;
if has_function_privilege('authenticated','private.hub_driver_vehicle_context_v1(uuid,uuid,date,date)','execute')or has_function_privilege('anon','private.hub_driver_goal_deviation_v1(numeric,numeric,numeric,bigint)','execute')then raise exception 'Private helpers exposed';end if;
end $tests$;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $tests$ declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';p uuid;r jsonb;v jsonb;a jsonb;begin
select k.object_id into p from public.hub_identity_keys k join public.kpi_transpa_time_facts tr on tr.tenant_id=k.tenant_id and tr.employee_id=k.identity_value
join public.hub_objects o on o.id=k.object_id and o.status='active'
where k.tenant_id=t and k.identity_type='transpa_employee_id' and k.confidence=1 and tr.work_date between '2026-10-01' and '2026-10-28'and jsonb_array_length(tr.transpa_vehicle_ids)>0 limit 1;
if p is null then raise exception 'No canonical person fixture';end if;
r:=public.hub_driver_self_v1(t,'2026-10-01','2026-10-28',p);
if jsonb_array_length(r->'vehicle_context')=0 then raise exception 'Expected vehicle context';end if;
for v in select value from jsonb_array_elements(r->'vehicle_context')loop
if v?|array['revenue','cost','amount','salary','unit_id','transactions']then raise exception 'Financial amount leaked';end if;
if v->>'goal_deviation_pct' is not null and abs((v->>'goal_deviation_pct')::numeric-(v->>'previous_goal_deviation_pct')::numeric-(v->>'change_vs_previous_pp')::numeric)>0.01 then raise exception 'Previous comparison arithmetic';end if;
if v->>'year_from'<>'2025-10-01' or v->>'year_to'<>'2025-10-28' then raise exception 'Year comparison dates';end if;
for a in select value from jsonb_array_elements(v->'actions')loop
if a->>'kind' in('emptying','load') and a->>'quantity' is not null then raise exception 'Unverified trip estimate';end if;
if a->>'kind'='fuel' and ((a->>'liters')::numeric<=0 or(a->>'gap_covered_pct')::numeric>100 or(a->>'gap_covered_pct')::numeric<0)then raise exception 'Fuel action limits';end if;
end loop;
end loop;
end $tests$;
select 'PASS: relative goals, zero/missing data, dated comparisons, bounded coaching, no amounts, private helpers' result;
rollback;
