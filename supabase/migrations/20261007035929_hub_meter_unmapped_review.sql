-- Preserve unresolved upstream evidence without guessing a canonical vehicle.
do $patch$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('public.hub_sync_fordonskontroll_meter_readings(uuid,uuid,text,jsonb)'::regprocedure);
 needle:='        skipped_n:=skipped_n+1;';
 if strpos(definition,needle)=0 then raise exception 'Meter skip contract changed';end if;
 execute replace(definition,needle,$replacement$
        if not exists(select 1 from public.hub_review_queue q
          where q.tenant_id=p_tenant_id and q.review_type='fordonskontrollen_meter_unmapped' and q.status='open'
          and q.payload->>'connection_id'=p_connection_id::text and q.payload->>'reading_type'=p_reading_type
          and q.payload->'record'=r) then
          insert into public.hub_review_queue(tenant_id,review_type,proposed_matches,payload,status)
          values(p_tenant_id,'fordonskontrollen_meter_unmapped','[]',jsonb_build_object(
            'source','fordonskontrollen','connection_id',p_connection_id,'reading_type',p_reading_type,
            'reason','Missing canonical asset, reading value or date','record',r),'open');
        end if;
        review_n:=review_n+1;
        skipped_n:=skipped_n+1;$replacement$);
end $patch$;
