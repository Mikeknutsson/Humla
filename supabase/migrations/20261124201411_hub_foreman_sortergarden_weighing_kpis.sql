-- Read registered Sortergården volumes from the canonical weighing events.
create function private.hub_foreman_weighing_kpis_v1(p_tenant uuid, p_from date, p_to date, p_user uuid, p_months integer[])
returns jsonb
language plpgsql stable security definer
set search_path to ''
as $function$
declare
 caller_role text;
 report jsonb;
begin
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366
    or (p_months is not null and (cardinality(p_months)=0 or array_position(p_months,null) is not null
        or not p_months <@ array[1,2,3,4,5,6,7,8,9,10,11,12])) then
  raise exception 'Invalid weighing period' using errcode='22023';
 end if;

 select m.role into caller_role
 from public.hub_tenant_members m
 where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active';

 if caller_role is null or p_user is null or (p_user<>auth.uid() and caller_role<>'owner')
    or not exists (
     select 1 from private.hub_foreman_access_plans p
     join public.hub_tenant_members m on m.tenant_id=p.tenant_id and m.user_id=p.auth_user_id and m.status='active'
     where p.tenant_id=p_tenant and p.auth_user_id=p_user and p.status='active'
      and '20'=any(p.cost_centers)
    ) then
  raise exception 'Sortergården access required' using errcode='42501';
 end if;

 with selected as materialized (
  select (e.occurred_at at time zone 'Europe/Stockholm')::date as local_date,
   e.direction,e.net_weight_kg as kg,
   nullif(btrim(e.source_metadata->>'stock_location'),'') as location,
   nullif(btrim(e.material_name),'') as material
  from public.hub_weighing_events e
  where e.tenant_id=p_tenant and e.facility_external_id='elleholms_sortergard'
   and e.source_system='elleholms_sortergard_excel'
   and e.direction in ('in','out') and e.measurement_status in ('observed','verified')
   and e.weight_unit='kg' and e.net_weight_kg>0
   and coalesce(e.source_metadata->>'external_delivery','false')<>'true'
   and e.occurred_at>=p_from::timestamp at time zone 'Europe/Stockholm'
   and e.occurred_at<(p_to+1)::timestamp at time zone 'Europe/Stockholm'
   and (p_months is null or extract(month from e.occurred_at at time zone 'Europe/Stockholm')::integer=any(p_months))
 ), stock_locations as (
  select location,
   coalesce(sum(kg) filter(where direction='in'),0)/1000 as incoming_tonnes,
   coalesce(sum(kg) filter(where direction='out'),0)/1000 as outgoing_tonnes,
   count(*) filter(where direction='in') as incoming_count,
   count(*) filter(where direction='out') as outgoing_count,
   sum(kg) as total_kg
  from selected group by location
 ), materials as (
  select location,material,
   coalesce(sum(kg) filter(where direction='in'),0)/1000 as incoming_tonnes,
   coalesce(sum(kg) filter(where direction='out'),0)/1000 as outgoing_tonnes,
   count(*) filter(where direction='in') as incoming_count,
   count(*) filter(where direction='out') as outgoing_count,
   sum(kg) as total_kg
  from selected group by location,material
 )
 select jsonb_build_object(
  'count',count(*),
  'incoming_count',count(*) filter(where direction='in'),
  'outgoing_count',count(*) filter(where direction='out'),
  'incoming_tonnes',coalesce(sum(kg) filter(where direction='in'),0)/1000,
  'outgoing_tonnes',coalesce(sum(kg) filter(where direction='out'),0)/1000,
  'days',count(distinct local_date),
  'latest_weighing',max(local_date),
  'locations',coalesce((select jsonb_agg(
   (to_jsonb(l)-'total_kg')||jsonb_build_object('materials',(
    select jsonb_agg(to_jsonb(m)-'total_kg'-'location' order by m.total_kg desc,m.material)
    from materials m where m.location is not distinct from l.location
   )) order by l.total_kg desc,l.location) from stock_locations l),'[]'::jsonb)
 ) into report from selected;
 return report;
end;
$function$;

create function public.hub_foreman_weighing_kpis_v1(
 p_tenant uuid,p_from date,p_to date,p_user uuid,p_months integer[] default null
) returns jsonb language sql stable security invoker set search_path to ''
as $function$
 select private.hub_foreman_weighing_kpis_v1(p_tenant,p_from,p_to,p_user,p_months)
$function$;

revoke all on function private.hub_foreman_weighing_kpis_v1(uuid,date,date,uuid,integer[]),
 public.hub_foreman_weighing_kpis_v1(uuid,date,date,uuid,integer[]) from public,anon,authenticated;
grant execute on function private.hub_foreman_weighing_kpis_v1(uuid,date,date,uuid,integer[]),
 public.hub_foreman_weighing_kpis_v1(uuid,date,date,uuid,integer[]) to authenticated;
