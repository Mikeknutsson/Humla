CREATE OR REPLACE FUNCTION public.hub_sync_fordonskontroll_meter_readings(p_tenant_id uuid, p_connection_id uuid, p_reading_type text, p_readings jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r jsonb;
  ext text;
  v_meter_external_type text;
  source_id text;
  source_type text;
  source_external_type text;
  asset_id uuid;
  object_id_value uuid;
  existing_data jsonb;
  canonical_data jsonb;
  ver integer;
  reading_value numeric;
  recorded_at timestamptz;
  candidate_ids uuid[];
  candidate_count integer;
  created_n integer:=0;
  matched_n integer:=0;
  updated_n integer:=0;
  review_n integer:=0;
  skipped_n integer:=0;
  failed_n integer:=0;
  errors jsonb:='[]'::jsonb;
begin
  if p_reading_type not in ('odometer_km','engine_hours') then
    raise exception 'Invalid reading type';
  end if;
  if not exists(
    select 1 from public.hub_connections
    where id=p_connection_id and tenant_id=p_tenant_id and connector_type='fordonskontrollen'
  ) then raise exception 'Invalid Fordonskontrollen connection'; end if;
  if jsonb_typeof(p_readings)<>'array' then raise exception 'p_readings must be a JSON array'; end if;

  v_meter_external_type:=case p_reading_type
    when 'odometer_km' then 'FordonskontrollOdometerReading'
    else 'FordonskontrollEngineHourReading'
  end;

  for r in select value from jsonb_array_elements(p_readings)
  loop
    begin
      ext:=nullif(coalesce(r->>'id',r->>'reading_id',r->>'readingId'),'');
      source_id:=nullif(coalesce(r#>>'{source,id}',r->>'source_id'),'');
      source_type:=lower(coalesce(r#>>'{source,type}',r->>'source_type',''));
      source_external_type:=case source_type
        when 'vehicle' then 'FordonskontrollVehicle'
        when 'vehicles' then 'FordonskontrollVehicle'
        when 'unit' then 'FordonskontrollUnit'
        when 'units' then 'FordonskontrollUnit'
        else null end;
      reading_value:=coalesce(
        nullif(r->>'value','')::numeric,
        nullif(r->>'reading','')::numeric,
        nullif(r->>'odometer','')::numeric,
        nullif(r->>'engine_hours','')::numeric
      );
      recorded_at:=coalesce(
        nullif(r->>'date','')::timestamptz,
        nullif(r->>'recorded_at','')::timestamptz,
        nullif(r->>'created_at','')::timestamptz
      );

      asset_id:=null;
      if source_id is not null and source_external_type is not null then
        select object_id into asset_id
        from public.hub_external_references
        where tenant_id=p_tenant_id and connection_id=p_connection_id
          and external_type=source_external_type and external_id=source_id limit 1;
      end if;

      if asset_id is null or reading_value is null or recorded_at is null then
        skipped_n:=skipped_n+1;
        continue;
      end if;

      if ext is null then
        ext:=source_type||':'||source_id||':'||p_reading_type||':'||
             to_char(recorded_at at time zone 'UTC','YYYYMMDDHH24MISS')||':'||reading_value::text;
      end if;

      object_id_value:=null;
      select object_id into object_id_value
      from public.hub_external_references
      where tenant_id=p_tenant_id and connection_id=p_connection_id
        and hub_external_references.external_type=v_meter_external_type and external_id=ext limit 1;

      canonical_data:=jsonb_build_object(
        'reading_type',p_reading_type,
        'reading_value',reading_value,
        'recorded_at',recorded_at,
        'asset_id',asset_id,
        'asset_type',source_type,
        'source_system','fordonskontrollen',
        'source_external_id',ext,
        'fordonskontrollen',r
      );

      if object_id_value is null then
        candidate_ids:=array(
          select o.id
          from public.hub_objects o
          where o.tenant_id=p_tenant_id
            and o.object_type='VehicleMeterReading'
            and o.data->>'reading_type'=p_reading_type
            and nullif(o.data->>'asset_id','')::uuid=asset_id
            and nullif(o.data->>'recorded_at','')::timestamptz=recorded_at
            and nullif(o.data->>'reading_value','')::numeric=reading_value
          limit 5
        );
        candidate_count:=coalesce(array_length(candidate_ids,1),0);

        if candidate_count=1 then
          object_id_value:=candidate_ids[1];
          matched_n:=matched_n+1;
        elsif candidate_count=0 then
          insert into public.hub_objects(
            tenant_id,object_type,status,data,source_of_truth,version
          ) values(
            p_tenant_id,'VehicleMeterReading','active',canonical_data,'fordonskontrollen',1
          ) returning id into object_id_value;
          insert into public.hub_object_versions(object_id,version,data,source_connection_id)
          values(object_id_value,1,canonical_data,p_connection_id);
          created_n:=created_n+1;
        else
          canonical_data:=canonical_data||jsonb_build_object(
            'duplicate_guard',jsonb_build_object(
              'status','ambiguous','candidate_ids',to_jsonb(candidate_ids)
            )
          );
          insert into public.hub_objects(
            tenant_id,object_type,status,data,source_of_truth,version
          ) values(
            p_tenant_id,'VehicleMeterReading','needs_review',canonical_data,'fordonskontrollen',1
          ) returning id into object_id_value;
          insert into public.hub_object_versions(object_id,version,data,source_connection_id)
          values(object_id_value,1,canonical_data,p_connection_id);
          insert into public.hub_review_queue(
            tenant_id,review_type,proposed_matches,payload,status,resolved_object_id
          ) values(
            p_tenant_id,'meter_reading_duplicate_ambiguous',to_jsonb(candidate_ids),
            jsonb_build_object('source','fordonskontrollen','external_id',ext,'record',r),
            'open',object_id_value
          );
          review_n:=review_n+1;
        end if;

        insert into public.hub_external_references(
          tenant_id,object_id,connection_id,external_type,external_id
        ) values(
          p_tenant_id,object_id_value,p_connection_id,v_meter_external_type,ext
        )
        on conflict(tenant_id,connection_id,external_type,external_id)
        do update set object_id=excluded.object_id;
      else
        select data,version into existing_data,ver
        from public.hub_objects where id=object_id_value for update;
        if existing_data is distinct from canonical_data then
          ver:=coalesce(ver,1)+1;
          update public.hub_objects
          set data=canonical_data,version=ver,updated_at=now()
          where id=object_id_value;
          insert into public.hub_object_versions(object_id,version,data,source_connection_id)
          values(object_id_value,ver,canonical_data,p_connection_id);
          updated_n:=updated_n+1;
        end if;
      end if;

      insert into public.hub_vehicle_meter_readings(
        tenant_id,object_id,vehicle_id,connection_id,reading_type,
        reading_value,recorded_at,external_id,raw_data
      ) values(
        p_tenant_id,object_id_value,asset_id,p_connection_id,p_reading_type,
        reading_value,recorded_at,ext,r
      )
      on conflict(tenant_id,connection_id,reading_type,external_id)
      do update set
        object_id=excluded.object_id,
        vehicle_id=excluded.vehicle_id,
        reading_value=excluded.reading_value,
        recorded_at=excluded.recorded_at,
        raw_data=excluded.raw_data;

    exception when others then
      failed_n:=failed_n+1;
      errors:=errors||jsonb_build_array(jsonb_build_object(
        'external_id',ext,'source_id',source_id,'error',sqlerrm
      ));
    end;
  end loop;

  return jsonb_build_object(
    'received',jsonb_array_length(p_readings),
    'humla_objects_created',created_n,
    'matched_existing',matched_n,
    'updated',updated_n,
    'sent_to_review',review_n,
    'skipped',skipped_n,
    'failed',failed_n,
    'errors',errors
  );
end;
$function$
;
