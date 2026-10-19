begin;
do $$
declare result jsonb;source jsonb;next_time jsonb;
begin
 source:='{"metrics":{},"driver_productivity":{"total_hours":8},"transpa_vehicle_time":{"vehicles":[{"vehicle":"AAA11A","hours":8,"available_hours":16},{"vehicle":"BBB22B","hours":0,"available_hours":160}]},"vehicles":[{"vehicle":"AAA11A","cost":100,"revenue":200,"cost_categories":{"fuel":40}},{"vehicle":"BBB22B","cost":10000,"revenue":20000,"cost_categories":{"fuel":4000}}],"economic_units":[]}';
 next_time:='{"available":true,"project_hours":6,"net_project_hours":4,"overlap_hours":2,"vehicles":[{"vehicle":"CCC33C","hours":4}],"units":[]}';
 result:=private.hub_kpi_worked_time_projection_v1(source,next_time,16);
 if(result#>>'{worked_time,worked_hours}')::numeric<>12 then raise exception 'Combined hours must add only net NEXT';end if;
 if(result#>>'{worked_time,eligible_vehicle_count}')::int<>2 then raise exception 'Zero-hour vehicle included or NEXT-only vehicle excluded';end if;
 if(result#>>'{worked_time,available_vehicle_hours}')::numeric<>32 then raise exception 'Capacity must include only positive-hour vehicles';end if;
 if(result#>>'{metrics,vehicle_utilization}')::numeric<>37.5 then raise exception 'Utilization denominator mismatch';end if;
 if(result#>>'{cost_efficiency,total_cost_per_hour}')::numeric<>8.33 then raise exception 'Cost from zero-hour vehicle leaked into numerator';end if;
 if(result#>>'{cost_efficiency,fuel_cost_per_hour}')::numeric<>3.33 then raise exception 'Fuel denominator mismatch';end if;
 if exists(select 1 from jsonb_array_elements(result->'vehicles')v where v->>'vehicle'='BBB22B'and v->>'cost_per_hour'is not null)then raise exception 'Zero-hour vehicle rate must be missing';end if;
 result:=private.hub_kpi_worked_time_projection_v1('{"metrics":{},"driver_productivity":{"total_hours":0},"vehicles":[],"economic_units":[]}', '{"available":false}',16);
 if result#>>'{worked_time,worked_hours}'is not null or result#>>'{metrics,vehicle_utilization}'is not null then raise exception 'Missing time must not become zero utilization';end if;
end$$;
select 'PASS merged net time, positive-hour fleet, NEXT-only capacity, matching costs, zero/missing time' as result;
rollback;
