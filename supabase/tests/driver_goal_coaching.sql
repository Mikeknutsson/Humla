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
select 'PASS: legacy relative helper is private and handles missing goals; driver UI uses complete-month percentage-point gap instead' result;
rollback;
