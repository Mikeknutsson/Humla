-- CORE-001: additive adapter from confirmed KPI units to shared Humla identities.
-- Monetary facts and historical KPI configuration remain untouched.
create or replace function private.hub_economic_member_v1(p_tenant uuid,p_kind text,p_reference text)
returns jsonb language sql stable security definer set search_path='' as $$
 with candidates as (
 select distinct public.hub_resolve_canonical_object_v1(p_tenant,k.object_id) id
 from public.hub_identity_keys k
 where k.tenant_id=p_tenant and upper(trim(k.identity_value))=upper(trim(p_reference))
 and ((p_kind='project' and k.object_type='Project' and k.identity_type='next_project_number')
 or (p_kind='person' and k.object_type='Person' and k.identity_type='employee_number')
 or (p_kind='vehicle' and k.object_type='Vehicle' and k.identity_type='registration_number'))
 ), verified as (
 select c.id from candidates c join public.hub_objects o on o.id=c.id and o.tenant_id=p_tenant
 where o.object_type=case p_kind when 'project' then 'Project' when 'person' then 'Person' when 'vehicle' then 'Vehicle' end
 )
 select jsonb_build_object('kind',p_kind,'source_reference',p_reference,
 'object_id',case when count(*)=1 then min(id::text)::uuid end,
 'resolution',case count(*) when 1 then 'confirmed' when 0 then 'missing_identity' else 'ambiguous_identity' end)
 from verified;
$$;
revoke all on function private.hub_economic_member_v1(uuid,text,text) from public,anon,authenticated;

create or replace function private.hub_sync_economic_unit_v1(p_tenant uuid,p_unit uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare u public.kpi_units; periods jsonb; payload jsonb; old public.hub_objects; v record; members jsonb; latest jsonb;
begin
 select * into u from public.kpi_units where tenant_id=p_tenant and id=p_unit for update;
 if not found or u.origin not in ('manual','manual_builder') then return null; end if;
 periods:='[]'::jsonb;
 for v in
  select p.id,p.valid_from,p.valid_to,p.payload,p.created_by from public.kpi_unit_periods p
   where p.tenant_id=p_tenant and p.unit_id=p_unit
  union all select null::uuid,u.valid_from,u.valid_to,to_jsonb(u),null::uuid
   where not exists(select 1 from public.kpi_unit_periods p where p.tenant_id=p_tenant and p.unit_id=p_unit)
  order by valid_from
 loop
  select coalesce(jsonb_agg(private.hub_economic_member_v1(p_tenant,r.kind,r.ref) order by r.kind,r.ref),'[]') into members
  from (
   select distinct kind,ref from (
    select 'project' kind,jsonb_array_elements_text(coalesce(v.payload->'projects','[]')) ref
    union all select 'vehicle',jsonb_array_elements_text(coalesce(v.payload->'registrations','[]'))
    union all select 'person',jsonb_array_elements_text(coalesce(v.payload->'employees','[]'))
   ) refs
  )r;
  periods:=periods||jsonb_build_array(jsonb_build_object('source_period_id',v.id,'valid_from',v.valid_from,'valid_to',v.valid_to,
   'name',coalesce(v.payload->>'name',u.name),'enabled',coalesce((v.payload->>'enabled')::boolean,u.enabled),
   'unit_type',coalesce(v.payload->>'unit_type',u.unit_type),'business_group_id',v.payload->>'business_group_id',
   'main_vehicle',case when v.payload->>'main_vehicle' is not null then private.hub_economic_member_v1(p_tenant,'vehicle',v.payload->>'main_vehicle') end,
   'members',members,'confirmed_by',v.created_by));
 end loop;
 latest:=periods->-1;
 payload:=jsonb_build_object('name',latest->>'name','unit_type',latest->>'unit_type','enabled',latest->'enabled',
  'periods',periods,'components',coalesce((select jsonb_agg(jsonb_build_object('source_component_id',c.id,
   'member',private.hub_economic_member_v1(p_tenant,case when c.component_type in ('person','driver') then 'person' when c.component_type='project' then 'project' else 'vehicle' end,c.component_reference),
   'role',c.component_type,'allocation_percent',c.allocation_percent,'valid_from',c.valid_from,'valid_to',c.valid_to)order by c.valid_from,c.id)
   from public.kpi_unit_components c where c.tenant_id=p_tenant and c.unit_id=p_unit),'[]'::jsonb),
  'adapter',jsonb_build_object('source','confirmed_kpi_mapping','kpi_unit_id',u.id,'revision',u.revision));
 select * into old from public.hub_objects where id=p_unit for update;
 if found then
  if old.tenant_id<>p_tenant or old.object_type<>'EconomicUnit' then raise exception 'Humla identity collision'; end if;
  if old.data=payload then return p_unit; end if;
  insert into public.hub_object_versions(object_id,version,data)values(old.id,old.version,old.data) on conflict do nothing;
  update public.hub_objects set data=payload,version=old.version+1,status=case when (latest->>'enabled')::boolean then 'active' else 'inactive' end where id=p_unit;
 else
  insert into public.hub_objects(id,tenant_id,object_type,status,data,source_of_truth,version)
   values(p_unit,p_tenant,'EconomicUnit',case when (latest->>'enabled')::boolean then 'active' else 'inactive' end,payload,'Humla',1);
 end if;
 insert into public.hub_identity_keys(tenant_id,object_id,object_type,identity_type,identity_value,confidence)
 values(p_tenant,p_unit,'EconomicUnit','kpi_unit_id',p_unit::text,1)on conflict do nothing;
 if not exists(select 1 from public.hub_identity_keys where tenant_id=p_tenant and identity_type='kpi_unit_id' and identity_value=p_unit::text and object_id=p_unit)then raise exception 'Economic unit identity conflict';end if;
 return p_unit;
end $$;
revoke all on function private.hub_sync_economic_unit_v1(uuid,uuid) from public,anon,authenticated;

create or replace function private.hub_sync_economic_unit_trigger_v1()returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='kpi_units' then
  perform private.hub_sync_economic_unit_v1(new.tenant_id,new.id);
 elsif tg_op='DELETE' then
  perform private.hub_sync_economic_unit_v1(old.tenant_id,old.unit_id);
 else
  perform private.hub_sync_economic_unit_v1(new.tenant_id,new.unit_id);
  if tg_op='UPDATE' and (old.unit_id,old.tenant_id) is distinct from (new.unit_id,new.tenant_id) then
   perform private.hub_sync_economic_unit_v1(old.tenant_id,old.unit_id);
  end if;
 end if;
 return null;
end $$;
revoke all on function private.hub_sync_economic_unit_trigger_v1() from public,anon,authenticated;
create trigger hub_economic_unit_sync after insert or update on public.kpi_units for each row execute function private.hub_sync_economic_unit_trigger_v1();
create trigger hub_economic_period_sync after insert or update or delete on public.kpi_unit_periods for each row execute function private.hub_sync_economic_unit_trigger_v1();
create trigger hub_economic_component_sync after insert or update or delete on public.kpi_unit_components for each row execute function private.hub_sync_economic_unit_trigger_v1();

-- An exact source identity arriving later completes only matching memberships.
create or replace function private.hub_economic_identity_refresh_v1()returns trigger
language plpgsql security definer set search_path='' as $$
declare k record;u record;field text;
begin
 for k in select new.tenant_id tenant_id,new.identity_type identity_type,new.identity_value identity_value
  union select old.tenant_id,old.identity_type,old.identity_value where tg_op in ('UPDATE','DELETE')
 loop
  field:=case k.identity_type when 'registration_number' then 'registrations' when 'employee_number' then 'employees' when 'next_project_number' then 'projects' end;
  if field is null then continue;end if;
  for u in select id from public.kpi_units x where x.tenant_id=k.tenant_id and x.origin in ('manual','manual_builder') and (
   to_jsonb(x)->field @> jsonb_build_array(k.identity_value)
   or exists(select 1 from public.kpi_unit_periods p where p.tenant_id=x.tenant_id and p.unit_id=x.id and p.payload->field @> jsonb_build_array(k.identity_value))
   or exists(select 1 from public.kpi_unit_components c where c.tenant_id=x.tenant_id and c.unit_id=x.id and c.component_reference=k.identity_value))
  loop perform private.hub_sync_economic_unit_v1(k.tenant_id,u.id);end loop;
 end loop;
 return null;
end $$;
revoke all on function private.hub_economic_identity_refresh_v1() from public,anon,authenticated;
create trigger hub_economic_identity_refresh after insert or update or delete on public.hub_identity_keys for each row execute function private.hub_economic_identity_refresh_v1();

-- Include all confirmed units, irrespective of whether a period has financial facts.
create or replace function public.hub_economic_units_catalog_v1(p_tenant uuid,p_date date default current_date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read') then raise exception 'KPI access required'; end if;
 if p_date is null then raise exception 'Date required';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'version',o.version,'name',coalesce(p.value->>'name',o.data->>'name'),
  'unit_type',o.data->>'unit_type','enabled',coalesce((p.value->>'enabled')::boolean,false),'active_on_date',p.value is not null,
  'current_period',p.value,'periods',o.data->'periods','components',o.data->'components',
  'business_group',g.name,'updated_at',o.updated_at)order by coalesce(p.value->>'name',o.data->>'name')),'[]') into result
 from public.hub_objects o
 left join lateral(select value from jsonb_array_elements(o.data->'periods') where (value->>'valid_from')::date<=p_date and ((value->>'valid_to')is null or (value->>'valid_to')::date>=p_date)order by (value->>'valid_from')::date desc limit 1)p on true
 left join public.kpi_business_groups g on g.tenant_id=p_tenant and g.id::text=p.value->>'business_group_id'
 where o.tenant_id=p_tenant and o.object_type='EconomicUnit';
 return jsonb_build_object('as_of',p_date,'units',result);
end $$;
revoke all on function public.hub_economic_units_catalog_v1(uuid,date) from public,anon;
grant execute on function public.hub_economic_units_catalog_v1(uuid,date) to authenticated;

do $$declare u record;begin
 for u in select tenant_id,id from public.kpi_units where origin in ('manual','manual_builder')loop
  perform private.hub_sync_economic_unit_v1(u.tenant_id,u.id);
 end loop;
end $$;
