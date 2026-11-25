create function private.hub_sortergard_address_batch(p_tenant uuid,p_year int,p_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or public.hub_has_permission(p_tenant,'kpi.manage') is not true then
  raise exception 'Behörighet saknas' using errcode='42501';
 end if;
 if p_year not between 2026 and 2100 or coalesce(cardinality(p_ids),0) not between 1 and 150 then
  raise exception 'Ogiltigt urval av vägningar';
 end if;
 return (
 with events as materialized (
  select e.id,e.raw_payload raw,(e.occurred_at at time zone 'Europe/Stockholm')::date event_day,
   case when e.source_metadata->>'external_delivery'='true' then 'Externleverans' else e.raw_payload->>'Leveranstyp' end kind
  from public.hub_weighing_events e
  left join private.hub_sortergard_addresses a on a.tenant_id=e.tenant_id and a.event_id=e.id
  where e.tenant_id=p_tenant and e.id=any(p_ids) and e.source_system='elleholms_sortergard_excel'
   and e.measurement_status<>'void' and a.status is distinct from 'verified'
   and e.occurred_at >= (make_date(p_year,1,1)::timestamp at time zone 'Europe/Stockholm')
   and e.occurred_at < (make_date(p_year+1,1,1)::timestamp at time zone 'Europe/Stockholm')
 ), hints as materialized (
  select e.id,btrim(v.hint) hint,v.label from events e cross join lateral (
   values(e.raw->>'Ordernr','Orderrad'),(e.raw->>'Referens','Referensrad'),
    (coalesce(nullif(e.raw->>'Projekt',''),e.raw->>'Projektnamn'),'Projekt')
  ) v(hint,label) where nullif(btrim(v.hint),'') is not null
 ), terms as materialized (
  select id,lower(hint) term from hints where length(hint) between 4 and 180 and hint !~* '^[a-z]{3}[0-9]{2}[a-z0-9]$'
  union
  select id,m[1] from hints cross join lateral regexp_matches(hint,'(?<![0-9])([0-9]{4,})(?![0-9])','g') m
 ), work_distinct as (
  select distinct t.id,w.source_data->>'Ordernummer' reference,w.source_data->>'Projekt' project,
   w.source_data->>'Rubrik' name,w.source_data->>'Kundnamn' customer,left(w.source_data->>'Platser',500) address
  from private.hub_workify_row_observations w
  cross join lateral unnest(array[lower(btrim(w.source_data->>'Ordernummer')),lower(btrim(w.source_data->>'ErReferens')),
   lower(btrim(w.source_data->>'VårReferens')),lower(btrim(w.source_data->>'Projekt'))]) keys(term)
  join terms t on t.term=keys.term
  join events e on e.id=t.id and left(coalesce(nullif(w.source_data->>'Artikeldatum',''),w.source_data->>'PlaneradStart'),10)
    between (e.event_day-90)::text and (e.event_day+90)::text
  where w.tenant_id=p_tenant
 ), work as materialized (
  select * from (select *,row_number() over(partition by id order by address nulls last,reference,project,name,customer) rank from work_distinct) w
  where rank<=12
 ), linked_orders as (
  select distinct t.id,n.payload p
  from public.hub_next_entities n cross join lateral unnest(array[
   n.payload->>'orderno',n.payload->>'workorderno',n.payload->>'externalworkorderno',
   n.payload->>'customerreference',n.payload->>'customerreference2']) keys(term)
  join terms t on t.term=lower(btrim(keys.term)) where n.tenant_id=p_tenant and n.entity_type='workorder'
 ), next_projects as (
  select n.payload,coalesce(nullif(n.payload->>'projectno',''),n.payload->>'projectnumber') reference,
   coalesce(nullif(n.payload->>'name',''),n.payload->>'projectname') name
  from public.hub_next_entities n where n.tenant_id=p_tenant and n.entity_type='project'
 ), project_matches as (
  select distinct t.id,n.* from next_projects n join terms t on t.term in (lower(btrim(n.reference)),lower(btrim(n.name)),lower(btrim(n.payload->>'orderno')))
   or (length(btrim(n.name))>=7 and strpos(t.term,lower(btrim(n.name)))>0)
  union
  select w.id,n.* from next_projects n join work w on nullif(lower(btrim(w.project)),'') in (lower(btrim(n.name)),lower(btrim(n.reference)))
  union
  select o.id,n.* from next_projects n join linked_orders o on nullif(o.p->>'projectid','') in(n.payload->>'id',n.reference)
 ), clues as (
  select id,'Workify' source,reference,project name,address,'Matchande arbetsorder eller projekt' reason,1 priority from work
  union all
  select distinct id,'Workify',reference,name,null,'Rubrik på matchande arbetsorder',2 from work where nullif(name,'') is not null and name is distinct from project
  union all
  select id,'Next',reference,name,case when nullif(btrim(payload->>'workplaceaddress1'),'') is not null then
   concat_ws(', ',payload->>'workplaceaddress1',nullif(btrim(payload->>'workplaceaddress2'),''),
    nullif(btrim(concat_ws(' ',payload->>'workplacezipcode',payload->>'workplacecity')),'')) end,
   'Matchande projekt eller kopplad arbetsorder',0 from project_matches
  union all
  select id,'Next',coalesce(p->>'workorderno',p->>'orderno'),p->>'projectname',location.label||': '||location.value,'Plats på matchande arbetsorder',0
  from linked_orders cross join lateral (values ('Från',p->>'startlocationtext'),('Till',p->>'stoplocationtext')) location(label,value)
  where nullif(btrim(location.value),'') is not null
  union all
  select id,'Flintab',null,hint,null,label,3 from hints
  union all
  select e.id,'AAK','AAK Karlshamn','AAK Sweden AB','Västra Kajen, 374 82 Karlshamn','AAK:s publicerade besöksadress',1
  from events e where private.hub_sortergard_is_aak(e.raw->>'Ordernr',e.raw->>'Referens',e.raw->>'Projekt',e.raw->>'Projektnamn',
    e.raw->>'Kund',e.raw->>'Kundnamn',case when e.kind='Inleverans' then e.raw->>'Avsändare (Id)' when e.kind='Utleverans' then e.raw->>'Mottagare (Id)' end)
   or exists(select 1 from work w where w.id=e.id and private.hub_sortergard_is_aak(w.project,w.customer))
   or exists(select 1 from project_matches n where n.id=e.id and private.hub_sortergard_is_aak(n.name))
 ), grouped as (
  select id,jsonb_agg(to_jsonb(c)-'id'-'priority' order by priority,source,reference,name,address) clues
  from (select distinct * from clues)c group by id
 )
 select coalesce(jsonb_object_agg(id,clues),'{}'::jsonb) from grouped
 );
end;
$$;

create function private.hub_sortergard_address_batch_save(p_tenant uuid,p_year int,p_candidates jsonb)
returns int language plpgsql security definer set search_path='' as $$
declare item jsonb; saved int:=0;
begin
 if auth.uid() is null or public.hub_has_permission(p_tenant,'kpi.manage') is not true then
  raise exception 'Behörighet saknas' using errcode='42501';
 end if;
 if jsonb_typeof(p_candidates) is distinct from 'array' or jsonb_array_length(p_candidates) not between 1 and 150 then
  raise exception 'Ogiltigt urval av adresser';
 end if;
 for item in select value from jsonb_array_elements(p_candidates) loop
  if private.hub_sortergard_use_address(p_tenant,p_year,(item->>'id')::uuid,item->'candidate') then saved:=saved+1; end if;
 end loop;
 return saved;
end;
$$;

create function public.hub_sortergard_address_batch(p_tenant uuid,p_year int,p_ids uuid[])
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.hub_sortergard_address_batch(p_tenant,p_year,p_ids)
$$;

create function public.hub_sortergard_address_batch_save(p_tenant uuid,p_year int,p_candidates jsonb)
returns int language sql security invoker set search_path='' as $$
 select private.hub_sortergard_address_batch_save(p_tenant,p_year,p_candidates)
$$;

revoke all on function private.hub_sortergard_address_batch(uuid,int,uuid[]),public.hub_sortergard_address_batch(uuid,int,uuid[]),
 private.hub_sortergard_address_batch_save(uuid,int,jsonb),public.hub_sortergard_address_batch_save(uuid,int,jsonb) from public,anon,authenticated;
grant execute on function private.hub_sortergard_address_batch(uuid,int,uuid[]),public.hub_sortergard_address_batch(uuid,int,uuid[]),
 private.hub_sortergard_address_batch_save(uuid,int,jsonb),public.hub_sortergard_address_batch_save(uuid,int,jsonb) to authenticated;
