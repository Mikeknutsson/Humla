create table private.hub_flintab_imports (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.hub_tenants(id),
 imported_by uuid,
 imported_at timestamptz not null default now(),
 filename text not null,
 sha256 text not null,
 workbook bytea not null,
 errors jsonb not null,
 summary jsonb not null default '{}',
 unique(tenant_id,sha256)
);
alter table private.hub_flintab_imports enable row level security;
revoke all on private.hub_flintab_imports from public, anon, authenticated;

create function private.hub_flintab_import(p_tenant uuid, p_file jsonb, p_rows jsonb, p_commit boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 batch_id uuid; item jsonb; record_id text; local_day date; kg numeric; kind text; payload jsonb;
 old public.hub_weighing_events%rowtype; object_id uuid; decision text;
 added int:=0; changed int:=0; unchanged int:=0; identical_file boolean:=false; digest text; bytes bytea;
begin
 if auth.uid() is null or public.hub_has_permission(p_tenant,'kpi.manage') is not true then
  raise exception 'Behörighet saknas' using errcode='42501';
 end if;
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 20000 or
   (select count(distinct v->>0) from jsonb_array_elements(p_rows) v) <> jsonb_array_length(p_rows) then
  raise exception 'Ogiltiga eller dubbla transaktioner';
 end if;
 if p_commit then
  perform pg_advisory_xact_lock(hashtextextended('flintab:'||p_tenant::text,0));
  bytes:=decode(p_file->>'base64','base64');
  digest:=encode(sha256(bytes),'hex');
  if bytes is null or octet_length(bytes) not between 1 and 2097152 or length(p_file->>'filename') not between 1 and 240 then
   raise exception 'Ogiltig originalfil';
  end if;
  select id into batch_id from private.hub_flintab_imports where tenant_id=p_tenant and sha256=digest;
  identical_file:=found;
  if not identical_file then
   insert into private.hub_flintab_imports(tenant_id,imported_by,filename,sha256,workbook,errors)
   values(p_tenant,auth.uid(),p_file->>'filename',digest,bytes,coalesce(p_file->'errors','[]')) returning id into batch_id;
  end if;
 end if;
 for item in select v from jsonb_array_elements(p_rows) v loop
  record_id:=item->>0; local_day:=(item->>1)::date; kg:=(item->>2)::numeric; kind:=item->>3;
  if record_id !~ '^[0-9]{1,32}$' or local_day not between date '2000-01-01' and date '2100-12-31'
   or kg not between 0 and 2000000 or kind not in ('in','out','external') then raise exception 'Ogiltig vägning'; end if;
  select jsonb_object_agg(k,item->(i+4)) into payload from unnest(array['TransId','Datum','Lastbärare','Avsändare (Id)','Mottagare (Id)','Referens','Ordernr','Artikel (Id)','Vikt','Lagerplats','Leveranstyp']) with ordinality t(k,n)
   cross join lateral (select n::int i) a;
  select * into old from public.hub_weighing_events e where e.tenant_id=p_tenant and e.source_system='elleholms_sortergard_excel' and e.source_record_id=record_id;
  if not found then decision:='new';
  elsif old.net_weight_kg=kg and (old.occurred_at at time zone 'Europe/Stockholm')::date=local_day
   and not exists(select 1 from jsonb_each_text(payload) p(k,v) where p.k not in ('Datum','Vikt','TransId')
      and coalesce(btrim(p.v),'')<>coalesce(btrim(old.raw_payload->>p.k),'')) then decision:='same';
  else decision:='changed'; end if;
  if identical_file or decision='same' then unchanged:=unchanged+1; continue; end if;
  if decision='new' then added:=added+1; else changed:=changed+1; end if;
  if not p_commit then continue; end if;
  object_id:=old.humla_object_id;
  if object_id is null then
   select k.object_id into object_id from public.hub_identity_keys k where k.tenant_id=p_tenant
    and k.object_type='WeighingEvent' and k.identity_type='yard_weighing_transaction'
    and k.identity_value='elleholms_sortergard:'||record_id;
   if object_id is null then
    insert into public.hub_objects(tenant_id,object_type,data,source_of_truth)
    values(p_tenant,'WeighingEvent',jsonb_build_object('display_name','Flintab '||record_id),'flintab_viktoria2')
    returning id into object_id;
    insert into public.hub_identity_keys(tenant_id,object_id,object_type,identity_type,identity_value)
    values(p_tenant,object_id,'WeighingEvent','yard_weighing_transaction','elleholms_sortergard:'||record_id);
   end if;
  end if;
  insert into public.hub_weighing_events(tenant_id,humla_object_id,source_system,source_record_id,ticket_number,weighing_type,occurred_at,
   facility_name,facility_external_id,vehicle_registration,material_code,material_name,net_weight_kg,weight_unit,direction,measurement_status,
   evidence_quality,raw_payload,source_metadata,order_reference)
  values(p_tenant,object_id,'elleholms_sortergard_excel',record_id,record_id,'weighbridge',(local_day+time '12:00') at time zone 'Europe/Stockholm',
   'Elleholms Maskin AB – Sortergården','elleholms_sortergard',nullif(upper(regexp_replace(payload->>'Lastbärare','[^[:alnum:]]','','g')),''),
   substring(payload->>'Artikel (Id)' from '\(([^()]+)\)\s*$'),btrim(regexp_replace(payload->>'Artikel (Id)','\s*\([^()]+\)\s*$','')),
   kg,'kg',case when kind='external' then 'unknown' else kind end,case when decision='changed' then 'corrected' else 'observed' end,
   'source_reported',payload,jsonb_build_object('import_id',batch_id,'file_name',p_file->>'filename','file_sha256',digest,'sheet',p_file->>'sheet','row_number',item->4,
    'external_delivery',kind='external','original_weight_unit','tonne','stock_location',payload->>'Lagerplats','cost_center','20','occurred_at_precision','date'),
   nullif(btrim(payload->>'Ordernr'),''))
  on conflict (tenant_id,source_system,source_record_id) where source_record_id is not null do update set
   humla_object_id=excluded.humla_object_id,occurred_at=excluded.occurred_at,vehicle_registration=excluded.vehicle_registration,
   material_code=excluded.material_code,material_name=excluded.material_name,net_weight_kg=excluded.net_weight_kg,
   direction=excluded.direction,measurement_status=excluded.measurement_status,raw_payload=excluded.raw_payload,
   source_metadata=excluded.source_metadata,order_reference=excluded.order_reference,updated_at=now();
 end loop;
 p_file:=jsonb_build_object('added',added,'changed',changed,'unchanged',unchanged,'id',batch_id,'alreadyImported',identical_file);
 if p_commit and not identical_file then update private.hub_flintab_imports set summary=p_file where id=batch_id; end if;
 return p_file;
end
$$;
create function public.hub_flintab_import(p_tenant uuid,p_file jsonb,p_rows jsonb,p_commit boolean)
returns jsonb language sql security invoker set search_path='' as $$
 select private.hub_flintab_import(p_tenant,p_file,p_rows,p_commit)
$$;
revoke all on function private.hub_flintab_import(uuid,jsonb,jsonb,boolean),public.hub_flintab_import(uuid,jsonb,jsonb,boolean) from public,anon,authenticated;
grant execute on function private.hub_flintab_import(uuid,jsonb,jsonb,boolean),public.hub_flintab_import(uuid,jsonb,jsonb,boolean) to authenticated;

create function private.hub_flintab_history(p_tenant uuid,p_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or public.hub_has_permission(p_tenant,'kpi.manage') is not true then raise exception 'Behörighet saknas' using errcode='42501'; end if;
 if p_id is not null then
  return (select jsonb_build_object('filename',filename,'base64',encode(workbook,'base64'),'errors',errors) from private.hub_flintab_imports where tenant_id=p_tenant and id=p_id);
 end if;
 return (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select id,filename,imported_at,summary,errors from private.hub_flintab_imports where tenant_id=p_tenant order by imported_at desc limit 50)x);
end
$$;
create function public.hub_flintab_history(p_tenant uuid,p_id uuid default null)
returns jsonb language sql stable security invoker set search_path='' as $$select private.hub_flintab_history(p_tenant,p_id)$$;
revoke all on function private.hub_flintab_history(uuid,uuid),public.hub_flintab_history(uuid,uuid) from public,anon,authenticated;
grant execute on function private.hub_flintab_history(uuid,uuid),public.hub_flintab_history(uuid,uuid) to authenticated;
