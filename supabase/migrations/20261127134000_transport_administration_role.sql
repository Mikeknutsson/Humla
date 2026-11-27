alter table public.hub_tenant_members
  drop constraint hub_tenant_members_role_check,
  add constraint hub_tenant_members_role_check
  check (role in ('owner','admin','management','economy','manager','supervisor','worker','transport_admin'));

insert into public.hub_permissions(code,name,description)
values ('transport.documents.use','Transportdokument','Skapa transportdokument och läsa de kunduppgifter som behövs för dokumentet.')
on conflict (code) do nothing;

insert into public.hub_role_permissions(role,permission_code)
values ('transport_admin','transport.documents.use')
on conflict do nothing;

CREATE OR REPLACE FUNCTION private.hub_ton_price_workify_customers(p_tenant_id uuid)
 RETURNS TABLE(name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select min(customer.name) as name
  from public.kpi_import_rows r
  join public.kpi_import_batches b on b.id = r.batch_id and b.tenant_id = r.tenant_id
  cross join lateral (select btrim(r.source_data->>'Kundnamn') as name) customer
  where r.tenant_id = p_tenant_id
    and (select public.hub_can_use_ton_price(p_tenant_id)
      or public.hub_has_permission(p_tenant_id,'transport.documents.use'))
    and r.data_kind = 'revenue' and r.is_valid
    and b.status in ('completed', 'needs_review')
    and (r.source_system = 'workify_file' or
      (r.source_system is null and r.source_data ?& array['Ordernummer','Artikelnummer','Artikeldatum']))
    and length(customer.name) between 1 and 240
  group by lower(customer.name)
  order by lower(customer.name);
$function$;

-- A document-only member uses explicit, field-limited RPCs instead of the general Hub policies.
create or replace function public.hub_has_tenant_access(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path='public' as $$
  select exists (
    select 1 from public.hub_tenant_members m join public.hub_tenants t on t.id=m.tenant_id
    where m.user_id=auth.uid() and m.tenant_id=p_tenant_id and m.status='active' and t.status='active'
      and m.role<>'transport_admin'
  )
$$;

create or replace function private.hub_transport_document_trucks(p_tenant uuid)
returns table(id uuid, registration text, name text)
language sql stable security definer set search_path='' as $$
  select o.id,o.data->>'registration_number',
    coalesce(nullif(o.data->>'vehicle_name',''),nullif(o.data->>'name',''),o.data->>'description')
  from public.hub_objects o
  where o.tenant_id=p_tenant and o.object_type='Vehicle' and o.status='active'
    and o.data->>'vehicle_type'='Lastbil'
    and (select public.hub_has_permission(p_tenant,'transport.documents.use')
             or public.hub_has_permission(p_tenant,'kpi.manage'))
$$;

create or replace function private.hub_transport_document_customer(p_tenant uuid, p_name text)
returns table(name text, organisation text, address text, source text)
language sql stable security definer set search_path='' as $$
  select o.data->>'display_name',o.data->>'organisation_number',o.data->>'postal_address',
    o.data->>'transport_contact_source_url'
  from public.hub_objects o
  where o.tenant_id=p_tenant and o.object_type='Customer' and o.status='active'
    and lower(o.data->>'display_name')=lower(btrim(p_name))
    and (select public.hub_has_permission(p_tenant,'transport.documents.use')
             or public.hub_has_permission(p_tenant,'kpi.manage'))
  limit 2
$$;

create or replace function public.hub_transport_document_trucks(p_tenant uuid)
returns table(id uuid, registration text, name text)
language sql stable security invoker set search_path='' as $$
  select * from private.hub_transport_document_trucks(p_tenant)
$$;

create or replace function public.hub_transport_document_customer(p_tenant uuid, p_name text)
returns table(name text, organisation text, address text, source text)
language sql stable security invoker set search_path='' as $$
  select * from private.hub_transport_document_customer(p_tenant,p_name)
$$;

revoke all on function private.hub_transport_document_trucks(uuid),
  private.hub_transport_document_customer(uuid,text), public.hub_transport_document_trucks(uuid),
  public.hub_transport_document_customer(uuid,text) from public,anon;
grant execute on function private.hub_transport_document_trucks(uuid),
  private.hub_transport_document_customer(uuid,text), public.hub_transport_document_trucks(uuid),
  public.hub_transport_document_customer(uuid,text) to authenticated;
