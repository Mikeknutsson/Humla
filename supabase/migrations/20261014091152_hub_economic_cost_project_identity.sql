-- NEXT cost projects already identify canonical Vehicles as well as Projects.
-- Resolve existing redirects; never create a competing Project identity.
create or replace function private.hub_economic_member_v1(p_tenant uuid,p_kind text,p_reference text)
returns jsonb language sql stable security definer set search_path='' as $$
 with candidates as (
 select distinct public.hub_resolve_canonical_object_v1(p_tenant,k.object_id) id
 from public.hub_identity_keys k
 where k.tenant_id=p_tenant and upper(trim(k.identity_value))=upper(trim(p_reference))
 and ((p_kind='project' and k.object_type in ('Project','Vehicle','vehicle') and k.identity_type in ('next_project_number','next_project_reference'))
 or (p_kind='person' and k.object_type='Person' and k.identity_type='employee_number')
 or (p_kind='vehicle' and k.object_type='Vehicle' and k.identity_type='registration_number'))
 ), verified as (
 select c.id from candidates c join public.hub_objects o on o.id=c.id and o.tenant_id=p_tenant
 where (p_kind='project' and o.object_type in ('Project','Vehicle')) or (p_kind='person' and o.object_type='Person') or (p_kind='vehicle' and o.object_type='Vehicle')
 )
 select jsonb_build_object('kind',p_kind,'source_reference',p_reference,
 'object_id',case when count(*)=1 then min(id::text)::uuid end,
 'resolution',case count(*) when 1 then 'confirmed' when 0 then 'missing_identity' else 'ambiguous_identity' end)
 from verified;
$$;
revoke all on function private.hub_economic_member_v1(uuid,text,text) from public,anon,authenticated;


do $$declare u record;begin for u in select tenant_id,id from public.kpi_units where origin in ('manual','manual_builder') loop perform private.hub_sync_economic_unit_v1(u.tenant_id,u.id); end loop;end $$;
