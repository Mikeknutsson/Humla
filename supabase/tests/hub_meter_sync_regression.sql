-- Run as database administrator against a seeded environment. Always rolls back.
begin;
do $test$
declare m public.hub_vehicle_meter_readings; r jsonb; result jsonb; before_count bigint; after_count bigint;
begin
 select * into m from public.hub_vehicle_meter_readings
 where raw_data is not null and reading_type='odometer_km' order by recorded_at desc limit 1;
 if not found then raise exception 'A mapped odometer reading is required';end if;
 select count(*) into before_count from public.hub_vehicle_meter_readings where tenant_id=m.tenant_id;
 r:=m.raw_data||jsonb_build_object('id','regression-alias-'||gen_random_uuid());
 result:=public.hub_sync_fordonskontroll_meter_readings(m.tenant_id,m.connection_id,m.reading_type,jsonb_build_array(r,r));
 if (result->>'failed')::int<>0 or (result->>'skipped')::int<>0 then raise exception 'Alias replay failed: %',result;end if;
 select count(*) into after_count from public.hub_vehicle_meter_readings where tenant_id=m.tenant_id;
 if before_count<>after_count then raise exception 'Alias created a duplicate domain reading';end if;
 r:=jsonb_build_object('id','regression-unmapped-'||gen_random_uuid(),'value',100,'date',now(),'source',jsonb_build_object('id','unmapped-regression','type','vehicle'));
 result:=public.hub_sync_fordonskontroll_meter_readings(m.tenant_id,m.connection_id,m.reading_type,jsonb_build_array(r,r));
 if (result->>'failed')::int<>0 or (result->>'skipped')::int<>2 or (result->>'sent_to_review')::int<>2 then raise exception 'Unmapped evidence was not retained: %',result;end if;
 select count(*) into after_count from public.hub_review_queue where tenant_id=m.tenant_id and review_type='fordonskontrollen_meter_unmapped' and payload->'record'=r;
 if after_count<>1 then raise exception 'Review replay created duplicates';end if;
end $test$;
rollback;
