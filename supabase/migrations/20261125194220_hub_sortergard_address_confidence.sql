create function private.hub_sortergard_is_aak(variadic fields text[])
returns boolean language sql immutable set search_path='' as $$
 select array_to_string(fields,' ') ~* '(^|[^[:alnum:]])(aak|aarhuskarlshamn)([^[:alnum:]]|$)'
$$;
revoke all on function private.hub_sortergard_is_aak(text[]) from public,anon,authenticated;

create or replace function private.hub_sortergard_address_clues(p_tenant uuid, p_year int, p_event uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or public.hub_has_permission(p_tenant,'kpi.manage') is not true then
  raise exception 'Behörighet saknas' using errcode='42501';
 end if;
 if p_year is null or p_year not between 2026 and extract(year from now() at time zone 'Europe/Stockholm') then
  return '[]'::jsonb;
 end if;
 return (
 with event as (
  select e.raw_payload->>'Ordernr' ord, e.raw_payload->>'Referens' ref,
    coalesce(nullif(e.raw_payload->>'Projekt',''),e.raw_payload->>'Projektnamn') project,
    coalesce(nullif(e.raw_payload->>'Kund',''),e.raw_payload->>'Kundnamn',
      case when e.raw_payload->>'Leveranstyp'='Inleverans' then e.raw_payload->>'Avsändare (Id)'
           when e.raw_payload->>'Leveranstyp'='Utleverans' then e.raw_payload->>'Mottagare (Id)' end) customer, (e.occurred_at at time zone 'Europe/Stockholm')::date as event_day
  from public.hub_weighing_events e
  where e.id=p_event and e.tenant_id=p_tenant and e.source_system='elleholms_sortergard_excel'
    and e.measurement_status<>'void'
    and e.occurred_at >= (make_date(p_year,1,1)::timestamp at time zone 'Europe/Stockholm')
    and e.occurred_at < (make_date(p_year+1,1,1)::timestamp at time zone 'Europe/Stockholm')
 ), hints as (
  select btrim(v.hint) hint, v.label
  from event e cross join lateral (values (e.ord,'Orderrad'),(e.ref,'Referensrad'),(e.project,'Projekt')) v(hint,label)
  where nullif(btrim(v.hint),'') is not null
 ), terms as (
  select distinct lower(hint) term from hints where length(hint) between 4 and 180
   and hint !~* '^[a-z]{3}[0-9]{2}[a-z0-9]$'
  union
  select distinct m[1] from hints cross join lateral regexp_matches(hint,'(?<![0-9])([0-9]{4,})(?![0-9])','g') m
 ), work as materialized (
  select distinct w.source_data->>'Ordernummer' reference, w.source_data->>'Projekt' project,
    w.source_data->>'Rubrik' name, w.source_data->>'Kundnamn' customer, left(w.source_data->>'Platser',500) address
  from private.hub_workify_row_observations w cross join event e
  where w.tenant_id=p_tenant
   and left(coalesce(nullif(w.source_data->>'Artikeldatum',''),w.source_data->>'PlaneradStart'),10)
     between (e.event_day-90)::text and (e.event_day+90)::text
   and exists (select 1 from terms where term in (
     lower(btrim(w.source_data->>'Ordernummer')), lower(btrim(w.source_data->>'ErReferens')),
     lower(btrim(w.source_data->>'VårReferens')), lower(btrim(w.source_data->>'Projekt'))))
  order by 5 asc nulls last,1,2,3,4 limit 12
 ), next_projects as materialized (
  select n.payload,
   coalesce(nullif(n.payload->>'projectno',''),n.payload->>'projectnumber') reference,
   coalesce(nullif(n.payload->>'name',''),n.payload->>'projectname') name
  from public.hub_next_entities n
  where n.tenant_id=p_tenant and n.entity_type='project'
 ), linked_orders as (
  select n.payload p
  from public.hub_next_entities n
  where n.tenant_id=p_tenant and n.entity_type='workorder'
    and exists(select 1 from terms where term in (
     lower(btrim(n.payload->>'orderno')), lower(btrim(n.payload->>'workorderno')),
     lower(btrim(n.payload->>'externalworkorderno')), lower(btrim(n.payload->>'customerreference')),
     lower(btrim(n.payload->>'customerreference2'))))
 ), projects as (
  select distinct n.reference,n.name,
   case when nullif(btrim(n.payload->>'workplaceaddress1'),'') is not null then
   concat_ws(', ',n.payload->>'workplaceaddress1',nullif(btrim(n.payload->>'workplaceaddress2'),''),
      nullif(btrim(concat_ws(' ',n.payload->>'workplacezipcode',n.payload->>'workplacecity')),'')) end address
  from next_projects n
  where exists(select 1 from terms where term in (
      lower(btrim(n.reference)),lower(btrim(n.name)),lower(btrim(n.payload->>'orderno')))
      or (length(btrim(n.name))>=7 and strpos(term,lower(btrim(n.name)))>0))
    or exists(select 1 from work w where nullif(lower(btrim(w.project)),'') in (lower(btrim(n.name)),lower(btrim(n.reference))))
    or exists(select 1 from linked_orders o where nullif(o.p->>'projectid','') in (n.payload->>'id',n.reference))
  order by 3 asc nulls last,1,2 limit 8
 ), clues as (
  select 'Workify' source,reference,project name,address,'Matchande arbetsorder eller projekt' reason,1 priority from work
  union all
  select distinct 'Workify',reference,name,null,'Rubrik på matchande arbetsorder',2 from work where nullif(name,'') is not null and name is distinct from project
  union all
  select 'Next',reference,name,address,'Matchande projekt eller kopplad arbetsorder',0 from projects
  union all
  select 'Next',coalesce(p->>'workorderno',p->>'orderno'),p->>'projectname',location.label || ': ' || location.value,
    'Plats på matchande arbetsorder',0
  from linked_orders cross join lateral (values ('Från',p->>'startlocationtext'),('Till',p->>'stoplocationtext')) location(label,value)
  where nullif(btrim(location.value),'') is not null
  union all
  select 'Flintab',null,hint,null,label,3 from hints
  union all
  select 'AAK','AAK Karlshamn','AAK Sweden AB','Västra Kajen, 374 82 Karlshamn',
    'AAK:s publicerade besöksadress',1
  where exists(select 1 from event where private.hub_sortergard_is_aak(ord,ref,project,customer))
    or exists(select 1 from work where private.hub_sortergard_is_aak(project,customer))
    or exists(select 1 from projects where private.hub_sortergard_is_aak(name))
 )
 select coalesce(jsonb_agg(to_jsonb(c)-'priority' order by priority,source,reference,name,address),'[]'::jsonb)
 from (select distinct * from clues order by priority,source,reference,name,address limit 36)c
 );
end;
$$;

create or replace function private.hub_sortergard_match(p_tenant uuid,p_year int,p_pending boolean)
returns jsonb language sql volatile set search_path='' as $$
 with all_rows as materialized (select * from private.hub_sortergard_data(p_tenant,p_year)),
 events as materialized (
  select d.*,lower(btrim(raw->>'Ordernr')) ord,lower(btrim(raw->>'Referens')) ref,
         lower(btrim(regexp_replace(material,'\s*\([^()]+\)\s*$',''))) mat
  from all_rows d
  where status<>'verified' and (not p_pending or status='pending')
 ), work as materialized (
  select distinct lower(btrim(source_data->>'Ordernummer')) ord,
    lower(btrim(source_data->>'ErReferens')) ref,
    lower(btrim(source_data->>'Projekt')) project,
    upper(regexp_replace(coalesce(nullif(source_data->>'RegNr',''),source_data->>'Fordon'),'[^[:alnum:]]','','g')) reg,
    left(coalesce(nullif(source_data->>'Artikeldatum',''),source_data->>'PlaneradStart'),10) as day,
    lower(btrim(source_data->>'Artikelnamn')) mat, source_data->>'Kundnamn' customer,
    case when lower(source_data->>'Enhet') in ('ton','t') and replace(source_data->>'Kvantitet',',','.') ~ '^[0-9]{1,7}(\.[0-9]{1,6})?$'
      then replace(source_data->>'Kvantitet',',','.')::numeric end tonnes,
    btrim(source_data->>'Platser') address
  from private.hub_workify_row_observations
  where tenant_id=p_tenant and nullif(btrim(source_data->>'Platser'),'') is not null
   and char_length(source_data->>'Platser')<=240 and source_data->>'Platser' !~ 'https?://|[;\n\r]'
   and source_data->>'Platser' ~ '[[:alpha:]].*[0-9]+.*,.*[0-9]{3} ?[0-9]{2} +[[:alpha:]]'
 ), projects as materialized (
  select distinct lower(btrim(coalesce(nullif(n.payload->>'projectno',''),k.identity_value))) project,
   lower(btrim(n.payload->>'orderno')) ord,n.payload->>'name' name,
   concat_ws(', ',nullif(btrim(n.payload->>'workplaceaddress1'),''),nullif(btrim(n.payload->>'workplaceaddress2'),''),
    nullif(btrim(concat_ws(' ',n.payload->>'workplacezipcode',n.payload->>'workplacecity')),'')) address
  from public.hub_next_entities n
  left join public.hub_identity_keys k on k.tenant_id=n.tenant_id and k.object_type='Project' and k.identity_type='next_project_number'
   and k.identity_value=n.payload->>'projectno'
  where n.tenant_id=p_tenant and n.entity_type='project' and nullif(btrim(n.payload->>'workplaceaddress1'),'') is not null
 ), candidates as (
  select e.id,w.address,'Workify' source,w.ord reference,
   case when e.ord=w.ord then 94 when e.ref=w.ord or e.ref=w.ref then 85 else 72 end score,
   case when e.ord=w.ord then 'Samma ordernummer' when e.ref=w.ord or e.ref=w.ref then 'Samma referens'
        else 'Samma registrering, datum, material och vikt' end reason
  from events e join work w on (nullif(e.ord,'')=w.ord or nullif(e.ref,'')=w.ord or nullif(e.ref,'')=nullif(w.ref,'')
    or (nullif(e.reg,'')=w.reg and e.day=w.day and e.mat=w.mat and abs(e.tonnes-w.tonnes)<=0.05
      and 1=(select count(*) from all_rows d where d.day=e.day and d.reg=e.reg and d.material=e.material and abs(d.tonnes-e.tonnes)<=0.05)))
  where e.kind in ('Inleverans','Utleverans')
  union all
  select e.id,p.address,'Next',p.project,
    case when e.ord in(p.project,p.ord) then 91 else 83 end,
    case when e.ord in(p.project,p.ord) then 'Samma projekt- eller ordernummer' else 'Referens motsvarar projektnummer' end
  from events e join projects p on nullif(e.ord,'') in(p.project,p.ord) or nullif(e.ref,'')=p.project
  where e.kind in ('Inleverans','Utleverans')
  union all
  select e.id,case when e.kind='Inleverans' then a.origin else a.destination end,'Verifierad historik',d.source_record_id,90,
    'Samma order, leveranstyp och material som en verifierad vägning'
  from events e join public.hub_weighing_events d on d.tenant_id=p_tenant and d.source_system='elleholms_sortergard_excel'
    and nullif(e.ord,'')=lower(btrim(d.raw_payload->>'Ordernr')) and e.kind=d.raw_payload->>'Leveranstyp'
    and e.material=d.raw_payload->>'Artikel (Id)' and abs((e.day::date-(d.occurred_at at time zone 'Europe/Stockholm')::date))<=90
    and coalesce(e.sender,'')=coalesce(d.raw_payload->>'Avsändare (Id)','') and coalesce(e.recipient,'')=coalesce(d.raw_payload->>'Mottagare (Id)','')
  join private.hub_sortergard_addresses a on a.tenant_id=p_tenant and d.id=a.event_id and a.status='verified'
  where e.kind in ('Inleverans','Utleverans')
  union all
  select e.id,'Västra Kajen, 374 82 Karlshamn','AAK','AAK Karlshamn',78,
    'AAK i projekt, order, referens eller kundfält. AAK:s publicerade besöksadress.'
  from events e
  where e.kind in ('Inleverans','Utleverans')
    and private.hub_sortergard_is_aak(e.raw->>'Projekt',e.raw->>'Projektnamn',e.ord,e.ref,e.raw->>'Kund',
      e.raw->>'Kundnamn',case when e.kind='Inleverans' then e.sender else e.recipient end)
 ), dedup as (
  select distinct on(id,lower(address)) id,address,source,reference,score,reason from candidates
  where nullif(btrim(address),'') is not null order by id,lower(address),score desc,source,reference
 ), ranked as (
  select *,row_number() over(partition by id order by score desc,address) rank from dedup
 ), results as (
  select id,jsonb_agg(jsonb_build_object('address',address,'source',source,'reference',reference,'score',score,'reason',reason) order by rank) options
  from ranked where rank<=8 group by id
 ), writes as (
  insert into private.hub_sortergard_addresses(tenant_id,event_id,status,candidates,origin,destination,source,reason,confidence)
  select p_tenant,e.id,case when r.options is null then 'missing' else 'likely' end,coalesce(r.options,'[]'),
   case when e.kind='Inleverans' then coalesce(r.options->0->>'address','') else '' end,
   case when e.kind='Utleverans' then coalesce(r.options->0->>'address','') else '' end,
   coalesce(r.options->0->>'source',''),
   case when r.options is null then 'Ingen tillräckligt underbyggd adress'
    when jsonb_array_length(r.options)>1 then 'Flera adresser behöver jämföras. '||(r.options->0->>'reason')
    else r.options->0->>'reason' end,
   coalesce((r.options->0->>'score')::int,0)
  from events e left join results r on r.id=e.id
  on conflict (tenant_id,event_id) do update set status=excluded.status,candidates=excluded.candidates,origin=excluded.origin,
   destination=excluded.destination,source=excluded.source,reason=excluded.reason,confidence=excluded.confidence,updated_at=now()
   where hub_sortergard_addresses.status<>'verified'
    and (hub_sortergard_addresses.source not like 'Adressbedömning:%' or hub_sortergard_addresses.confidence<excluded.confidence)
  returning status
 ) select jsonb_build_object('likely',count(*) filter(where status='likely'),'missing',count(*) filter(where status='missing'),'processed',count(*)) from writes
$$;

create function private.hub_sortergard_use_address(p_tenant uuid,p_year int,p_event uuid,p_candidate jsonb)
returns boolean language plpgsql security definer set search_path='' as $$
declare
 kind text;
 addr text := btrim(p_candidate->>'address');
 points int := (p_candidate->>'score')::int;
 attribution text := p_candidate->>'source';
begin
 if auth.uid() is null or public.hub_has_permission(p_tenant,'kpi.manage') is not true then
  raise exception 'Behörighet saknas' using errcode='42501';
 end if;
 if p_year is null or p_year not between 2026 and extract(year from now() at time zone 'Europe/Stockholm')
  or addr is null or length(addr) not between 4 and 240 or points is null or points not between 51 and 99
  or attribution is null or attribution not in ('AAK','Flintab','Next','Workify') then return false;
 end if;
 select e.raw_payload->>'Leveranstyp' into kind from public.hub_weighing_events e
 where e.tenant_id=p_tenant and e.id=p_event and e.source_system='elleholms_sortergard_excel'
  and e.measurement_status<>'void' and e.source_metadata->>'external_delivery' is distinct from 'true'
  and e.occurred_at >= (make_date(p_year,1,1)::timestamp at time zone 'Europe/Stockholm')
  and e.occurred_at < (make_date(p_year+1,1,1)::timestamp at time zone 'Europe/Stockholm');
 if kind is null or kind not in ('Inleverans','Utleverans') then return false; end if;
 insert into private.hub_sortergard_addresses(tenant_id,event_id,status,origin,destination,candidates,source,reason,confidence)
 values(p_tenant,p_event,'likely',case when kind='Inleverans' then addr else '' end,
   case when kind='Utleverans' then addr else '' end,jsonb_build_array(p_candidate),
   'Adressbedömning: '||attribution,left(coalesce(p_candidate->>'reason',''),240),points)
 on conflict(tenant_id,event_id) do update set status='likely',origin=excluded.origin,destination=excluded.destination,
   candidates=excluded.candidates,source=excluded.source,reason=excluded.reason,confidence=excluded.confidence,updated_at=now()
 where hub_sortergard_addresses.status<>'verified' and hub_sortergard_addresses.confidence<excluded.confidence;
 return found;
end;
$$;
create function public.hub_sortergard_use_address(p_tenant uuid,p_year int,p_event uuid,p_candidate jsonb)
returns boolean language sql security invoker set search_path='' as $$
 select private.hub_sortergard_use_address(p_tenant,p_year,p_event,p_candidate)
$$;
revoke all on function private.hub_sortergard_use_address(uuid,int,uuid,jsonb),public.hub_sortergard_use_address(uuid,int,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.hub_sortergard_use_address(uuid,int,uuid,jsonb),public.hub_sortergard_use_address(uuid,int,uuid,jsonb) to authenticated;
