CREATE OR REPLACE FUNCTION private.hub_sortergard_data(p_tenant uuid, p_year integer)
 RETURNS TABLE(id uuid, trans_id text, day text, reg text, sender text, recipient text, material text, tonnes numeric, stock text, kind text, status text, origin text, destination text, source text, reason text, confidence integer, candidates jsonb, raw jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with facilities as materialized (
  select k.identity_value, nullif(btrim(o.data->>'address'),'') address
  from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=p_tenant
  where k.tenant_id=p_tenant and k.object_type='CustomerFacility' and k.identity_type='flintab_party_fallback'
   and o.object_type='CustomerFacility' and o.status='active'
 ), rules as materialized (
  select k.identity_value, nullif(btrim(o.data->>'address'),'') address,
   o.data->>'address_rule_mode' mode, o.data->>'address_rule_reason' reason
  from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
  where k.tenant_id=p_tenant and k.object_type='CustomerFacility' and k.identity_type='flintab_party_address_rule'
   and o.object_type='CustomerFacility' and o.status='active'
 )
 select e.id,e.source_record_id,to_char(e.occurred_at at time zone 'Europe/Stockholm','YYYY-MM-DD'),e.vehicle_registration,
 e.raw_payload->>'Avsändare (Id)',e.raw_payload->>'Mottagare (Id)',coalesce(e.raw_payload->>'Artikel (Id)',e.material_name),
 e.net_weight_kg/1000,e.raw_payload->>'Lagerplats',delivery.kind,
 case when applied.origin is not null or applied.destination is not null then
  case when not address_result.complete then 'missing'
       when delivery.kind='Utleverans' and destination_rule.mode='confirmed' then 'verified'
       else 'fallback' end
  when fallback.complete then 'fallback' else coalesce(a.status,'pending') end,
 address_result.origin,address_result.destination,
 case when applied.origin is not null or applied.destination is not null then 'Sparad adressregel'
  when fallback.origin is not null or fallback.destination is not null then 'Kundens anläggningsadress' else coalesce(a.source,'') end,
 case when applied.origin is not null or applied.destination is not null then concat_ws(' ',
  case when applied.origin is not null then origin_rule.reason end,
  case when applied.destination is not null and (applied.origin is null or destination_rule.reason is distinct from origin_rule.reason) then destination_rule.reason end,
  case when not address_result.complete then 'Adress för den andra parten saknas.' end)
  when fallback.complete then 'Reservadress för identifierad Flintabkund. Faktisk plats för vägningen är inte verifierad.'
  when fallback.origin is not null or fallback.destination is not null then 'Anläggningsadress finns för ena parten. Den andra adressen saknas.'
  else coalesce(a.reason,'') end,
 case when applied.destination is not null and delivery.kind='Utleverans' and destination_rule.mode='confirmed' then 100
      when applied.origin is not null or applied.destination is not null then 0 else coalesce(a.confidence,0) end,
 case when applied.origin is not null or applied.destination is not null then '[]'::jsonb else coalesce(a.candidates,'[]') end,e.raw_payload
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
 left join rules origin_rule on a.status is distinct from 'verified'
  and delivery.kind in ('Inleverans','Externleverans')
  and origin_rule.identity_value=private.hub_flintab_party_facility_key(e.raw_payload->>'Avsändare (Id)')||':origin'
 left join rules destination_rule on a.status is distinct from 'verified'
  and delivery.kind in ('Utleverans','Externleverans')
  and destination_rule.identity_value=private.hub_flintab_party_facility_key(e.raw_payload->>'Mottagare (Id)')||':destination'
  and (destination_rule.mode<>'confirmed' or delivery.kind='Utleverans')
 cross join lateral (select
  case when origin_rule.mode in ('preferred','confirmed') and origin_rule.address is distinct from nullif(a.origin,'')
         or origin_rule.mode='fallback' and nullif(a.origin,'') is null then origin_rule.address end as origin,
  case when destination_rule.mode='confirmed' or destination_rule.mode='preferred' and destination_rule.address is distinct from nullif(a.destination,'')
         or destination_rule.mode='fallback' and nullif(a.destination,'') is null then destination_rule.address end as destination) applied
 cross join lateral (select coalesce(applied.origin,fallback.origin,a.origin,'') as origin,
  coalesce(applied.destination,fallback.destination,a.destination,'') as destination) resolved
 cross join lateral (select resolved.*,
  case delivery.kind when 'Inleverans' then resolved.origin<>''
    when 'Utleverans' then resolved.destination<>''
    when 'Externleverans' then resolved.origin<>'' and resolved.destination<>''
    else false end as complete) address_result
 where e.tenant_id=p_tenant and e.source_system='elleholms_sortergard_excel' and e.measurement_status<>'void'
 and e.occurred_at >= (make_date(p_year,1,1)::timestamp at time zone 'Europe/Stockholm')
 and e.occurred_at < (make_date(p_year+1,1,1)::timestamp at time zone 'Europe/Stockholm')
 order by e.occurred_at,e.source_record_id
$function$;
