-- 9009 is a display/source alias of the existing hired-truck canonical Vehicle.
insert into public.hub_identity_keys(tenant_id,object_id,object_type,identity_type,identity_value,confidence)
select k.tenant_id,min(k.object_id::text)::uuid,'Vehicle','workify_vehicle_label','9009',1
from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
where k.identity_type='registration_number' and k.identity_value='INHYRDLASTBIL' and k.confidence=1 and o.object_type='Vehicle'
group by k.tenant_id having count(distinct k.object_id)=1
on conflict(tenant_id,object_type,identity_type,identity_value) do nothing;

create or replace function public.hub_kpi_review_options_v1(p_tenant_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'Behörighet saknas';end if;
 return jsonb_build_object('projects',coalesce((select jsonb_agg(jsonb_build_object('value',p.project_number,'label',concat_ws(' – ',p.project_number,nullif(p.project_name,''))) order by p.project_number)
 from public.kpi_next_project_register p where p.tenant_id=p_tenant_id),'[]'),
 'vehicles',coalesce((select jsonb_agg(jsonb_build_object('value',v.registration,'label',case when v.registration='9009' then '9009 – Inhyrda' else v.registration end) order by v.registration)
 from (select distinct case when o.data->>'registration_number'='INHYRDLASTBIL' then '9009' else o.data->>'registration_number' end registration
 from public.hub_objects o where o.tenant_id=p_tenant_id and o.object_type='Vehicle' and nullif(o.data->>'registration_number','') is not null)v),'[]'));
end $$;
revoke all on function public.hub_kpi_review_options_v1(uuid) from public,anon;
grant execute on function public.hub_kpi_review_options_v1(uuid) to authenticated;

do $patch$ declare definition text; old_validation text; begin
 definition:=pg_get_functiondef('public.kpi_approve_review(uuid,jsonb,text)'::regprocedure);
 old_validation:=$old$if v.vehicle_registration is not null and v.vehicle_registration !~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then raise exception 'Giltigt registreringsnummer krävs'; end if;$old$;
 if position(old_validation in definition)=0 then raise exception 'Unexpected review validation definition';end if;
 definition:=replace(definition,old_validation,$new$if v.vehicle_registration is not null and v.vehicle_registration !~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$'
 and not exists(select 1 from public.hub_identity_keys k where k.tenant_id=r.tenant_id and k.object_type='Vehicle' and k.confidence=1
 and k.identity_type in ('registration_number','workify_vehicle_label') and k.identity_value=v.vehicle_registration)
 then raise exception 'Välj ett registrerat fordon från Hubben';end if;$new$);
 definition:=replace(definition,'update public.kpi_import_rows set occurred_on=v.occurred_on',
 $new$-- Resolve the confirmed display alias to the existing canonical vehicle and reporting unit.
 if v.vehicle_registration in ('9009','LASTBIL','INHYRDLASTBIL') then
  v.vehicle_registration:='LASTBIL';v.project_reference:='9009';
 end if;
 select case when count(distinct k.object_id)=1 then min(k.object_id::text)::uuid end into v.vehicle_object_id
 from public.hub_identity_keys k where k.tenant_id=r.tenant_id and k.object_type='Vehicle' and k.confidence=1
 and k.identity_type in ('registration_number','workify_vehicle_label') and k.identity_value=v.vehicle_registration;
 update public.kpi_import_rows set occurred_on=v.occurred_on$new$);
 definition:=replace(definition,'vehicle_object_id=null,employee_number=v.employee_number','vehicle_object_id=v.vehicle_object_id,employee_number=v.employee_number');
 execute definition;
 definition:=pg_get_functiondef('public.kpi_approve_workify_order_review(uuid,jsonb,text)'::regprocedure);
 definition:=replace(definition,'vehicle_registration=approved.vehicle_registration,vehicle_object_id=null','vehicle_registration=approved.vehicle_registration,vehicle_object_id=approved.vehicle_object_id');
 execute definition;
end $patch$;
