create function private.orderportal_maintenance_overlap(p_tenant_id uuid,p_vehicle text,p_start text,p_end text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare r record; a timestamptz; b timestamptz;
begin
 if nullif(p_vehicle,'') is null then return false;end if;
 for r in select o.data->'fordonskontroll' d from public.hub_objects o
 join public.hub_external_references e on e.object_id=o.id and e.tenant_id=p_tenant_id and e.external_type='FordonskontrollWorkOrder'
 join private.orderportal_maintenance_sync s on s.connection_id=e.connection_id and s.tenant_id=p_tenant_id and s.source_ids ? e.external_id
 where o.tenant_id=p_tenant_id and o.object_type='WorkOrder' and o.source_of_truth='fordonskontrollen'
 and o.data->>'source_object_id'=p_vehicle and nullif(o.data#>>'{fordonskontroll,completed_at}','') is null
 loop
  begin
   if coalesce(r.d->>'start','') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' or coalesce(r.d->>'end','') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' then continue;end if;
   a:=(r.d->>'start')::timestamptz;b:=(r.d->>'end')::timestamptz;
  exception when others then continue;end;
  if b>a and a<((p_end::timestamp) at time zone 'Europe/Stockholm') and ((p_start::timestamp) at time zone 'Europe/Stockholm')<b then return true;end if;
 end loop;
 return false;
end $$;
revoke all on function private.orderportal_maintenance_overlap(uuid,text,text,text) from public,anon,authenticated;
do $patch$
declare d text;needle text:='for v_line in select value from jsonb_array_elements(p_payload->''lines'') loop';
begin
 d=pg_get_functiondef('private.orderportal_save_priced(uuid,uuid,integer,uuid,jsonb)'::regprocedure);
 if position(needle in d)=0 then raise exception 'Planning guard insertion point missing';end if;
 d=replace(d,needle,$guard$
 if p_payload->>'status' in ('Utkast','Planerad','Pågående') and private.orderportal_maintenance_overlap(p_tenant_id,p_payload->>'vehicleId',p_payload->>'start',p_payload->>'end') then raise exception 'maintenance_conflict';end if;
 for v_line in select value from jsonb_array_elements(p_payload->'lines') loop$guard$);
 execute d;
end $patch$;
