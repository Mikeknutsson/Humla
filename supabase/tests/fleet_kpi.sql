-- Run in a transaction; production fixtures are read only, synthetic meters roll back.
begin;
set local request.jwt.claim.sub='5a6fa4c4-5427-47fa-9835-d997fe81c7d5';
do $$
declare tenant uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';r jsonb;detail jsonb;a jsonb;asset uuid;conn uuid;expected numeric;v numeric;objects uuid[]:=array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
begin
 r:=public.hub_fleet_kpi_v1(tenant,2025,array[9,10,11,12,1,2,3,4,5,6,7,8]);
 select sum((x->>'cost')::numeric) into expected from jsonb_array_elements(r->'assets') x;
 if expected<>(r#>>'{summary,cost}')::numeric then raise exception 'Asset sum mismatch';end if;
 select sum((x->>'amount')::numeric) into expected from jsonb_array_elements(r->'components') x;
 if expected<>(r#>>'{summary,cost}')::numeric then raise exception 'Component sum mismatch';end if;
 select sum((x->>'cost')::numeric) into expected from jsonb_array_elements(r->'monthly') x;
 if expected<>(r#>>'{summary,cost}')::numeric then raise exception 'Month sum mismatch';end if;
 select x into a from jsonb_array_elements(r->'assets') x where (x->>'cost_rows')::int>0 limit 1;asset:=(a->>'id')::uuid;
 detail:=public.hub_fleet_kpi_v1(tenant,2025,array[9,10,11,12,1,2,3,4,5,6,7,8],asset);
 select sum((x->>'amount')::numeric) into expected from jsonb_array_elements(detail->'evidence') x;
 if jsonb_array_length(detail->'evidence')<>(detail->>'evidence_count')::int or expected<>(a->>'cost')::numeric then raise exception 'Evidence sum mismatch';end if;
 if exists(select 1 from jsonb_array_elements(detail->'evidence') x where x->>'component'='personnel' or x->>'source'='TransPA') then raise exception 'Salary leak';end if;
 if r::text like '%"revenue"%' or r::text like '%"personnel"%' then raise exception 'Financial disclosure';end if;
 if exists(select 1 from jsonb_array_elements(r->'assets') x where (x->>'missing_months')::int>0 and x->>'cost_per_unit' is not null) then raise exception 'Incomplete distance got ratio';end if;
 detail:=public.hub_fleet_kpi_v1(tenant,2025,array[11],null,'Transport');
 if exists(select 1 from jsonb_array_elements(detail->'assets') x where x->>'department'<>'Transport') then raise exception 'Department filter failed';end if;
 if jsonb_array_length(detail->'monthly')<>1 or detail#>>'{monthly,0,date}'<>'2025-11-01' then raise exception 'Month filter failed';end if;
 detail:=public.hub_fleet_kpi_v1(tenant,2090,array[9]);
 if detail#>>'{summary,cost}' is not null or jsonb_array_length(detail->'monthly')<>0 then raise exception 'Future period fabricated cost';end if;
 begin perform public.hub_fleet_kpi_v1(tenant,2025,array[0]);raise exception 'Invalid month accepted';exception when raise_exception then if sqlerrm='Invalid month accepted' then raise;end if;end;
 select connection_id into conn from public.hub_vehicle_meter_readings where tenant_id=tenant limit 1;
 insert into public.hub_objects(id,tenant_id,object_type,data) select id,tenant,'VehicleMeterReading',jsonb_build_object('test','fleet_kpi') from unnest(objects) id;
 insert into public.hub_vehicle_meter_readings(tenant_id,vehicle_id,connection_id,reading_type,reading_value,recorded_at,external_id,object_id)
 values(tenant,asset,conn,'engine_hours',100,'2001-09-01 00:00 Europe/Stockholm','test-fleet-'||gen_random_uuid(),objects[1]),
 (tenant,asset,conn,'engine_hours',200,'2001-10-01 00:00 Europe/Stockholm','test-fleet-'||gen_random_uuid(),objects[2]);
 detail:=private.hub_fleet_meter_usage_v1(tenant,asset,'engine_hours','2001-09-01','2001-09-30');
 if detail->>'basis'<>'meter_exact' or (detail->>'value')::numeric<>100 then raise exception 'Engine hours failed';end if;
 detail:=private.hub_fleet_meter_usage_v1(tenant,asset,'engine_hours','2001-09-10','2001-09-19');
 v:=(detail->>'value')::numeric;
 if detail->>'basis'<>'interpolated' or abs(v-100::numeric/3)>0.0001 then raise exception 'Engine interpolation failed';end if;
 insert into public.hub_vehicle_meter_readings(tenant_id,vehicle_id,connection_id,reading_type,reading_value,recorded_at,external_id,object_id)
 values(tenant,asset,conn,'engine_hours',50,'2001-09-15 00:00 Europe/Stockholm','test-fleet-'||gen_random_uuid(),objects[3]);
 if private.hub_fleet_meter_usage_v1(tenant,asset,'engine_hours','2001-09-01','2001-09-30')->>'basis'<>'invalid_meter_sequence' then raise exception 'Decreasing meter accepted';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 begin perform public.hub_fleet_kpi_v1(tenant,2025,array[11]);raise exception 'Unauthorized report accepted';exception when insufficient_privilege then null;end;
end $$;
rollback;
