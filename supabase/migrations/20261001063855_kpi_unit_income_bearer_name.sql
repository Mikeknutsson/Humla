CREATE OR REPLACE FUNCTION public.hub_kpi_save_unit_v2(p_tenant_id uuid, p_payload jsonb, p_unit_id uuid DEFAULT NULL::uuid, p_revision integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid; old public.kpi_units; effective date; ending date; latest date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI administrator required'; end if;
 if p_payload->>'unit_type' in ('vehicle','compound') and jsonb_array_length(p_payload->'registrations')>0 then
  if nullif(trim(p_payload->>'main_vehicle'),'') is null and jsonb_array_length(p_payload->'registrations')=1 then p_payload:=jsonb_set(p_payload,'{main_vehicle}',p_payload->'registrations'->0);end if;
  if nullif(trim(p_payload->>'main_vehicle'),'') is null or not (p_payload->'registrations' @> jsonb_build_array(p_payload->>'main_vehicle')) then raise exception 'Select an income-bearing main vehicle from the unit registrations';end if;
  p_payload:=jsonb_set(p_payload,'{name}',to_jsonb(p_payload->>'main_vehicle'));
 end if;
 effective:=(p_payload->>'valid_from')::date;ending:=nullif(p_payload->>'valid_to','')::date;
 if effective is null or (ending is not null and ending<effective) or length(trim(p_payload->>'name')) not between 1 and 120 or p_payload->>'unit_type' not in ('vehicle','person','overhead','compound') then raise exception 'Invalid unit';end if;
 if jsonb_array_length(p_payload->'projects')+jsonb_array_length(p_payload->'registrations')+jsonb_array_length(p_payload->'employees') not between 1 and 300 then raise exception 'Select 1-300 references';end if;
 if exists(select 1 from jsonb_array_elements_text(p_payload->'registrations') r where r !~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$') then raise exception 'Invalid registration';end if;
 if p_unit_id is null then
  insert into public.kpi_units(tenant_id,name,unit_type,projects,registrations,employees,valid_from,valid_to,enabled,origin)
  values(p_tenant_id,trim(p_payload->>'name'),p_payload->>'unit_type',array(select jsonb_array_elements_text(p_payload->'projects')),array(select jsonb_array_elements_text(p_payload->'registrations')),array(select jsonb_array_elements_text(p_payload->'employees')),effective,ending,coalesce((p_payload->>'enabled')::boolean,true),'manual') returning id into uid;
 else
  select * into old from public.kpi_units where id=p_unit_id and tenant_id=p_tenant_id for update;
  if not found or old.revision<>p_revision then raise exception 'Unit changed; reload before saving';end if;
  select max(valid_from) into latest from public.kpi_unit_periods where unit_id=old.id;
  if effective<=coalesce(latest,old.valid_from) then raise exception 'New composition must start after the latest period; history cannot be overwritten';end if;
  if latest is null then insert into public.kpi_unit_periods(tenant_id,unit_id,valid_from,valid_to,payload,created_by) values(p_tenant_id,old.id,old.valid_from,least(effective-1,coalesce(old.valid_to,effective-1)),to_jsonb(old),auth.uid());
  else update public.kpi_unit_periods set valid_to=effective-1 where unit_id=old.id and valid_from=latest and (valid_to is null or valid_to>=effective);end if;
  uid:=old.id;
  -- Current register fields are a display cache; historical queries use periods.
  update public.kpi_units set name=trim(p_payload->>'name'),unit_type=p_payload->>'unit_type',projects=array(select jsonb_array_elements_text(p_payload->'projects')),registrations=array(select jsonb_array_elements_text(p_payload->'registrations')),employees=array(select jsonb_array_elements_text(p_payload->'employees')),enabled=coalesce((p_payload->>'enabled')::boolean,true) where id=uid;
 end if;
 insert into public.kpi_unit_periods(tenant_id,unit_id,valid_from,valid_to,payload,created_by) values(p_tenant_id,uid,effective,ending,p_payload,auth.uid());
 return uid;
end $function$
