create function private.hub_sortergard_address_clues(p_tenant uuid, p_year int, p_event uuid)
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
    e.raw_payload->>'Projekt' project, (e.occurred_at at time zone 'Europe/Stockholm')::date as event_day
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
    w.source_data->>'Rubrik' name, left(w.source_data->>'Platser',500) address
  from private.hub_workify_row_observations w cross join event e
  where w.tenant_id=p_tenant
   and left(coalesce(nullif(w.source_data->>'Artikeldatum',''),w.source_data->>'PlaneradStart'),10)
     between (e.event_day-90)::text and (e.event_day+90)::text
   and exists (select 1 from terms where term in (
     lower(btrim(w.source_data->>'Ordernummer')), lower(btrim(w.source_data->>'ErReferens')),
     lower(btrim(w.source_data->>'VårReferens')), lower(btrim(w.source_data->>'Projekt'))))
  order by 4 asc nulls last,1,2,3 limit 12
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
 )
 select coalesce(jsonb_agg(to_jsonb(c)-'priority' order by priority,source,reference,name,address),'[]'::jsonb)
 from (select distinct * from clues order by priority,source,reference,name,address limit 36)c
 );
end;
$$;

create function public.hub_sortergard_address_clues(p_tenant uuid, p_year int, p_event uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.hub_sortergard_address_clues(p_tenant,p_year,p_event)
$$;

revoke all on function private.hub_sortergard_address_clues(uuid,int,uuid),public.hub_sortergard_address_clues(uuid,int,uuid) from public,anon,authenticated;
grant execute on function private.hub_sortergard_address_clues(uuid,int,uuid),public.hub_sortergard_address_clues(uuid,int,uuid) to authenticated;
