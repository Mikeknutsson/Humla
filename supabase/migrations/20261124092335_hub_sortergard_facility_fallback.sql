create function private.hub_flintab_party_facility_key(p_party text) returns text
language sql immutable set search_path='' as $$
 select case when p_party ~ '^.+ \([0-9]+\)[[:space:]]*$'
   and btrim(p_party) !~* '^(elleholms?|ellehoms?|används ej|okänd|diverse|kontant|privatkund)([[:space:]]|$)'
 then 'elleholms_sortergard:'||lower(regexp_replace(btrim(p_party),'[[:space:]]+',' ','g')) end
$$;
revoke all on function private.hub_flintab_party_facility_key(text) from public,anon,authenticated;

create or replace function private.hub_sortergard_data(p_tenant uuid,p_year int)
returns table(id uuid, trans_id text, day text, reg text, sender text, recipient text, material text, tonnes numeric,
 stock text, kind text, status text, origin text, destination text, source text, reason text, confidence int, candidates jsonb, raw jsonb)
language sql stable set search_path='' as $$
 with facilities as materialized (
  select k.identity_value, nullif(btrim(o.data->>'address'),'') address
  from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=p_tenant
  where k.tenant_id=p_tenant and k.object_type='CustomerFacility' and k.identity_type='flintab_party_fallback'
   and o.object_type='CustomerFacility' and o.status='active'
 )
 select e.id,e.source_record_id,to_char(e.occurred_at at time zone 'Europe/Stockholm','YYYY-MM-DD'),e.vehicle_registration,
 e.raw_payload->>'Avsändare (Id)',e.raw_payload->>'Mottagare (Id)',coalesce(e.raw_payload->>'Artikel (Id)',e.material_name),
 e.net_weight_kg/1000,e.raw_payload->>'Lagerplats',delivery.kind,
 case when fallback.complete then 'fallback' else coalesce(a.status,'pending') end,
 coalesce(fallback.origin,a.origin,''),coalesce(fallback.destination,a.destination,''),
 case when fallback.origin is not null or fallback.destination is not null then 'Kundens anläggningsadress' else coalesce(a.source,'') end,
 case when fallback.complete then 'Reservadress för identifierad Flintabkund. Faktisk plats för vägningen är inte verifierad.'
  when fallback.origin is not null or fallback.destination is not null then 'Anläggningsadress finns för ena parten. Den andra adressen saknas.'
  else coalesce(a.reason,'') end,
 coalesce(a.confidence,0),coalesce(a.candidates,'[]'),e.raw_payload
 from public.hub_weighing_events e
 left join private.hub_sortergard_addresses a on a.tenant_id=e.tenant_id and a.event_id=e.id
 cross join lateral (select case when e.source_metadata->>'external_delivery'='true' then 'Externleverans' else e.raw_payload->>'Leveranstyp' end as kind) delivery
 left join facilities sender on a.status='missing' and delivery.kind in ('Inleverans','Externleverans')
  and sender.identity_value=private.hub_flintab_party_facility_key(e.raw_payload->>'Avsändare (Id)')
 left join facilities recipient on a.status='missing' and delivery.kind in ('Utleverans','Externleverans')
  and recipient.identity_value=private.hub_flintab_party_facility_key(e.raw_payload->>'Mottagare (Id)')
 cross join lateral (select sender.address origin,recipient.address destination,
  case delivery.kind when 'Inleverans' then sender.address is not null when 'Utleverans' then recipient.address is not null
   when 'Externleverans' then sender.address is not null and recipient.address is not null else false end complete) fallback
 where e.tenant_id=p_tenant and e.source_system='elleholms_sortergard_excel' and e.measurement_status<>'void'
 and e.occurred_at >= (make_date(p_year,1,1)::timestamp at time zone 'Europe/Stockholm')
 and e.occurred_at < (make_date(p_year+1,1,1)::timestamp at time zone 'Europe/Stockholm')
 order by e.occurred_at,e.source_record_id
$$;

create function private.hub_sortergard_facility(p_tenant uuid,p_year int,p_event uuid,p_side text,p_address text)
returns void language plpgsql security definer set search_path='' as $$
declare entry record; party text; facility_key text; facility_id uuid;
begin
 if auth.uid() is null or public.hub_has_permission(p_tenant,'kpi.manage') is not true then
  raise exception 'Behörighet saknas' using errcode='42501';
 end if;
 p_address:=nullif(btrim(p_address),'');
 if p_year is null or p_year not between 2026 and 2100 or p_side is null or p_side not in ('origin','destination')
  or p_address is null or length(p_address)>240 then raise exception 'Ange en giltig anläggningsadress'; end if;
 select d.* into entry from private.hub_sortergard_data(p_tenant,p_year) d where d.id=p_event;
 if not found or entry.status not in ('missing','fallback') or entry.kind not in ('Inleverans','Utleverans','Externleverans')
  or (p_side='origin' and entry.kind='Utleverans') or (p_side='destination' and entry.kind='Inleverans') then
  raise exception 'Reservadress kan anges för obevisade vägningar där en specifik adress saknas';
 end if;
 party:=case when p_side='origin' then entry.sender else entry.recipient end;
 facility_key:=private.hub_flintab_party_facility_key(party);
 if facility_key is null then raise exception 'Flintabraden saknar en entydigt identifierad extern kund'; end if;
 perform pg_advisory_xact_lock(hashtextextended('flintab-site:'||p_tenant::text||':'||facility_key,0));
 select object_id into facility_id from public.hub_identity_keys where tenant_id=p_tenant and object_type='CustomerFacility'
  and identity_type='flintab_party_fallback' and identity_value=facility_key;
 if facility_id is null then
  insert into public.hub_objects(tenant_id,object_type,data,source_of_truth)
  values(p_tenant,'CustomerFacility',jsonb_build_object('display_name',party,'address',p_address,'address_source','Registrerad av användare','updated_by',auth.uid()),'humla_flintab')
  returning id into facility_id;
  insert into public.hub_identity_keys(tenant_id,object_id,object_type,identity_type,identity_value)
  values(p_tenant,facility_id,'CustomerFacility','flintab_party_fallback',facility_key);
 else
  update public.hub_objects set data=data||jsonb_build_object('address',p_address,'address_source','Registrerad av användare','updated_by',auth.uid()),updated_at=now()
  where tenant_id=p_tenant and id=facility_id and object_type='CustomerFacility' and source_of_truth='humla_flintab';
 end if;
end
$$;
create function public.hub_sortergard_facility(p_tenant uuid,p_year int,p_event uuid,p_side text,p_address text)
returns void language sql security invoker set search_path='' as $$
 select private.hub_sortergard_facility(p_tenant,p_year,p_event,p_side,p_address)
$$;
revoke all on function private.hub_sortergard_facility(uuid,int,uuid,text,text),public.hub_sortergard_facility(uuid,int,uuid,text,text) from public,anon,authenticated;
grant execute on function private.hub_sortergard_facility(uuid,int,uuid,text,text),public.hub_sortergard_facility(uuid,int,uuid,text,text) to authenticated;
