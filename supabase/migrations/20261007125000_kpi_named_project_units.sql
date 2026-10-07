CREATE OR REPLACE FUNCTION public.hub_kpi_save_unit_v2(p_tenant_id uuid, p_payload jsonb, p_unit_id uuid DEFAULT NULL::uuid, p_revision integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 uid uuid; old public.kpi_units; effective date; ending date; latest date;
 today date := (now() at time zone 'Europe/Stockholm')::date;
 initial boolean := coalesce((p_payload->>'initial_setup')::boolean,false);
 finalize boolean := coalesce((p_payload->>'finalize_setup')::boolean,false);
 is_open boolean; period_count integer; previous_periods jsonb; last_payload jsonb;
 group_id uuid; first_start date; next_start date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then
  raise exception 'KPI-administratör krävs';
 end if;
 if p_unit_id is not null then
  select * into old from public.kpi_units where id=p_unit_id and tenant_id=p_tenant_id for update;
  if not found or old.revision is distinct from p_revision then raise exception 'Enheten har ändrats. Ladda om innan du sparar';end if;
  select count(*),max(valid_from),coalesce(jsonb_agg(to_jsonb(p) order by valid_from),'[]')
   into period_count,latest,previous_periods from public.kpi_unit_periods p where p.unit_id=old.id and p.tenant_id=p_tenant_id;
  select payload into last_payload from public.kpi_unit_periods where unit_id=old.id and tenant_id=p_tenant_id order by case when initial then valid_from end asc,valid_from desc limit 1;
  -- Preserve provenance and omitted optional fields; explicit null removes an own group.
  p_payload:=coalesce(last_payload,'{}')||p_payload;
  select locked_at is null into is_open from public.kpi_unit_initial_setup where unit_id=old.id and tenant_id=p_tenant_id;
  is_open:=coalesce(is_open,false);
  if initial and (not is_open or period_count<1) then raise exception 'Grundkopplingen är låst. Historiken får inte skrivas om';end if;
 end if;
 if p_payload->>'unit_type' in ('vehicle','compound') and jsonb_array_length(p_payload->'registrations')>0 then
  if nullif(trim(p_payload->>'main_vehicle'),'') is null and jsonb_array_length(p_payload->'registrations')=1 then
   p_payload:=jsonb_set(p_payload,'{main_vehicle}',p_payload->'registrations'->0);
  end if;
  if nullif(trim(p_payload->>'main_vehicle'),'') is null or not (p_payload->'registrations' @> jsonb_build_array(p_payload->>'main_vehicle')) then
   raise exception 'Välj intäktsbärande huvudfordon bland enhetens regnummer';
  end if;
  p_payload:=jsonb_set(p_payload,'{name}',to_jsonb(p_payload->>'main_vehicle'));
 end if;
 effective:=(p_payload->>'valid_from')::date;ending:=nullif(p_payload->>'valid_to','')::date;
 if p_unit_id is not null and initial then
  select min(valid_from) into first_start from public.kpi_unit_periods where unit_id=old.id and tenant_id=p_tenant_id;
  select min(valid_from) into next_start from public.kpi_unit_periods where unit_id=old.id and tenant_id=p_tenant_id and valid_from>first_start;
  if next_start is not null then
   if effective>=next_start or (ending is not null and ending>=next_start) then raise exception 'Grundkopplingen måste sluta före nästa ändringsperiod';end if;
   ending:=coalesce(ending,next_start-1);
   p_payload:=jsonb_set(p_payload,'{valid_to}',to_jsonb(ending));
  end if;
 end if;
 if effective is null or (ending is not null and ending<effective)
  or coalesce(length(trim(p_payload->>'name')),0) not between 1 and 120
  or coalesce(p_payload->>'unit_type','') not in ('vehicle','person','overhead','project','compound') then raise exception 'Ogiltiga enhetsuppgifter';end if;
 if jsonb_typeof(p_payload->'projects') is distinct from 'array'
  or jsonb_typeof(p_payload->'registrations') is distinct from 'array'
  or jsonb_typeof(p_payload->'employees') is distinct from 'array' then raise exception 'Ogiltiga referenslistor';end if;
 if jsonb_array_length(p_payload->'projects')+jsonb_array_length(p_payload->'registrations')+jsonb_array_length(p_payload->'employees') not between 1 and 300 then raise exception 'Ange 1–300 referenser';end if;
 if p_payload->>'unit_type'='project' and (jsonb_array_length(p_payload->'projects')<1 or jsonb_array_length(p_payload->'registrations')>0 or jsonb_array_length(p_payload->'employees')>0) then raise exception 'En projekt- eller materialenhet behöver projektkoppling och anges utan fordons- eller personreferenser';end if;
 if exists(select 1 from jsonb_array_elements_text(p_payload->'registrations') r where r !~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$') then raise exception 'Ogiltigt regnummer';end if;
 group_id:=nullif(p_payload->>'business_group_id','')::uuid;
 if group_id is not null and not exists(select 1 from public.kpi_business_groups where id=group_id and tenant_id=p_tenant_id and enabled) then raise exception 'Välj en aktiv verksamhetsgrupp i samma arbetsyta';end if;
 p_payload:=p_payload-'initial_setup'-'finalize_setup';
 if p_unit_id is null then
  insert into public.kpi_units(tenant_id,name,unit_type,projects,registrations,employees,valid_from,valid_to,enabled,origin)
  values(p_tenant_id,trim(p_payload->>'name'),p_payload->>'unit_type',
   array(select jsonb_array_elements_text(p_payload->'projects')),array(select jsonb_array_elements_text(p_payload->'registrations')),
   array(select jsonb_array_elements_text(p_payload->'employees')),effective,ending,coalesce((p_payload->>'enabled')::boolean,true),'manual') returning id into uid;
  insert into public.kpi_unit_initial_setup(unit_id,tenant_id,locked_at,locked_by)
   values(uid,p_tenant_id,case when finalize then now() end,case when finalize then auth.uid() end);
  insert into public.kpi_unit_initial_setup_events(tenant_id,unit_id,actor,action,next_payload)
   values(p_tenant_id,uid,auth.uid(),'create_initial',p_payload);
 else
  uid:=old.id;
  if initial then
   -- Archive the complete draft before correcting it. Locked history never enters this branch.
   insert into public.kpi_unit_initial_setup_events(tenant_id,unit_id,actor,action,previous_periods,next_payload)
    values(p_tenant_id,uid,auth.uid(),case when finalize then 'lock_initial' else 'correct_initial' end,previous_periods,p_payload);
   delete from public.kpi_unit_periods where unit_id=uid and tenant_id=p_tenant_id and valid_from=first_start;
  else
   if effective<today then raise exception 'Efter grundkopplingen får ändringar inte bakåtdateras. Välj idag eller senare';end if;
   if effective<=coalesce(latest,old.valid_from) then raise exception 'Ny koppling måste börja efter senaste periodens start';end if;
   if latest is null then
    insert into public.kpi_unit_periods(tenant_id,unit_id,valid_from,valid_to,payload,created_by)
    values(p_tenant_id,uid,old.valid_from,least(effective-1,coalesce(old.valid_to,effective-1)),to_jsonb(old),auth.uid());
   else
    update public.kpi_unit_periods set valid_to=effective-1 where unit_id=uid and valid_from=latest and (valid_to is null or valid_to>=effective);
   end if;
   if is_open then
    insert into public.kpi_unit_initial_setup_events(tenant_id,unit_id,actor,action,previous_periods,next_payload)
     values(p_tenant_id,uid,auth.uid(),'lock_initial',previous_periods,p_payload);
   end if;
  end if;
  if (initial and finalize) or not initial then
   update public.kpi_unit_initial_setup set locked_at=coalesce(locked_at,now()),locked_by=coalesce(locked_by,auth.uid())
    where unit_id=uid and tenant_id=p_tenant_id;
  end if;
  if not initial or period_count=1 then
  update public.kpi_units set name=trim(p_payload->>'name'),unit_type=p_payload->>'unit_type',
   projects=array(select jsonb_array_elements_text(p_payload->'projects')),
   registrations=array(select jsonb_array_elements_text(p_payload->'registrations')),
   employees=array(select jsonb_array_elements_text(p_payload->'employees')),enabled=coalesce((p_payload->>'enabled')::boolean,true),
   valid_from=case when initial then effective else valid_from end,
   valid_to=case when initial then ending else valid_to end
   where id=uid;
  else
   update public.kpi_units set valid_from=effective where id=uid;
  end if;
 end if;
 insert into public.kpi_unit_periods(tenant_id,unit_id,valid_from,valid_to,payload,created_by)
  values(p_tenant_id,uid,effective,ending,p_payload,auth.uid());
 return uid;
end $function$
