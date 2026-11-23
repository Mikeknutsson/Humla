-- This tenant setting holds a website-restricted, publishable Maps key.
-- OAuth credentials, service accounts and server keys belong to their own server integrations.
create table private.hub_google_maps_settings (
  tenant_id uuid primary key references public.hub_tenants(id) on delete cascade,
  browser_api_key text check (browser_api_key ~ '^AIza[A-Za-z0-9_-]{20,90}$'),
  updated_at timestamptz not null default now(),
  updated_by uuid not null
);
alter table private.hub_google_maps_settings enable row level security;
revoke all on private.hub_google_maps_settings from public, anon, authenticated;

create function private.hub_google_maps_config(p_tenant uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.hub_tenant_members
    where tenant_id = p_tenant and user_id = auth.uid() and status = 'active'
  ) then raise exception 'permission_denied' using errcode = '42501'; end if;

  return (select jsonb_build_object('browser_api_key', browser_api_key, 'updated_at', updated_at)
    from private.hub_google_maps_settings where tenant_id = p_tenant);
end;
$$;

create function private.hub_google_maps_save(p_tenant uuid, p_browser_api_key text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.hub_tenant_members
    where tenant_id = p_tenant and user_id = auth.uid() and status = 'active' and role = 'owner'
  ) then raise exception 'permission_denied' using errcode = '42501'; end if;

  insert into private.hub_google_maps_settings (tenant_id, browser_api_key, updated_by)
  values (p_tenant, trim(p_browser_api_key), auth.uid())
  on conflict (tenant_id) do update set
    browser_api_key = excluded.browser_api_key, updated_at = now(), updated_by = excluded.updated_by;
end;
$$;

create function public.hub_google_maps_config(p_tenant uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.hub_google_maps_config(p_tenant)
$$;
create function public.hub_google_maps_save(p_tenant uuid, p_browser_api_key text)
returns void language sql security invoker set search_path = '' as $$
  select private.hub_google_maps_save(p_tenant, p_browser_api_key)
$$;
revoke all on function private.hub_google_maps_config(uuid), private.hub_google_maps_save(uuid,text),
  public.hub_google_maps_config(uuid), public.hub_google_maps_save(uuid,text) from public, anon, authenticated;
grant execute on function private.hub_google_maps_config(uuid), private.hub_google_maps_save(uuid,text),
  public.hub_google_maps_config(uuid), public.hub_google_maps_save(uuid,text) to authenticated;
