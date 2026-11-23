-- Material sites are canonical Hub objects. Old purchase lists are read from their source.
create table private.hub_material_site_rates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.hub_tenants(id),
  site_id uuid not null references public.hub_objects(id),
  kind text not null check (kind in ('purchase', 'tip')),
  material text not null check (length(material) between 1 and 160),
  unit text not null check (unit in ('ton', 'm³', 'lass', 'st')),
  price numeric(12,4) not null check (abs(price) <= 1000000 and (kind = 'tip' or price >= 0)),
  valid_from date not null,
  valid_to date check (valid_to is null or valid_to >= valid_from),
  source text not null check (length(source) between 1 and 240),
  created_by uuid not null,
  created_at timestamptz not null default now()
);
create unique index hub_material_site_rates_version
  on private.hub_material_site_rates (tenant_id, site_id, kind, lower(material), unit, valid_from);
alter table private.hub_material_site_rates enable row level security;
revoke all on private.hub_material_site_rates from public, anon, authenticated;

do $seed$
declare entry record; site uuid;
begin
  for entry in
    select distinct p.tenant_id, seed.*
    from private.hub_kpi_internal_purchase_prices p
    join (values
      ('KYLLINGE','Johanssons Kylinge','quarry','','Kylinge 1:4, Sölvesborg','https://bransch.trafikverket.se/contentassets/be607b1d7a5f414e8440dc6bd4106c2f/samradsredogorelse_low.pdf'),
      ('SCHWEDEN_SPLITT','Schweden Splitt','quarry','Elleholmsvägen 230-130, 375 91 Mörrum','','https://www.schwedensplitt.se/kontakt/'),
      ('ONNESTAD','Önnestad','quarry','Källundavägen 281-15, 291 93 Önnestad','','https://swerock.se/kontakt/skane/onnestad-bergtakt/'),
      ('OSSJO','Össjö','quarry','Mossajordbovägen 116, 266 91 Munka Ljungby','','https://www.skanska.com/se/sv/produkter-tjanster/byggprodukter/bergmaterial-och-schaktmassor/kontakt/grus-och-kross-ossjo-munka-ljungby'),
      ('VAMBASA','Vambåsa','quarry','Grevavägen 11, 373 34 Nättraby','','https://www.skanska.com/se/sv/produkter-tjanster/byggprodukter/bergmaterial-och-schaktmassor/kontakt/grus-och-kross-vambasa-nattraby'),
      ('PUKAVIK','Sortergården Pukavik','both','','Pukavik 3:4','')
    ) as seed(key, name, kind, address, location_note, address_source)
      on p.supplier_key = seed.key or (p.supplier_key = 'KYLLINGE' and seed.key = 'PUKAVIK')
  loop
    if exists(select 1 from public.hub_identity_keys k where k.tenant_id = entry.tenant_id
      and k.object_type = 'MaterialSite' and k.identity_type = 'purchase_list_site' and k.identity_value = entry.key) then
      continue;
    end if;
    insert into public.hub_objects (tenant_id, object_type, data, source_of_truth)
    values (entry.tenant_id, 'MaterialSite', jsonb_build_object('display_name', entry.name, 'kind', entry.kind,
      'address', entry.address, 'location_note', entry.location_note, 'address_source', entry.address_source), 'humla_price_bank')
    returning id into site;
    insert into public.hub_identity_keys (tenant_id, object_id, object_type, identity_type, identity_value)
    values (entry.tenant_id, site, 'MaterialSite', 'purchase_list_site', entry.key);
  end loop;
end
$seed$;

create function private.hub_material_price_bank(p_tenant uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare sites jsonb; rates jsonb;
begin
  if auth.uid() is null or not coalesce(public.hub_has_permission(p_tenant, 'kpi.read'),false)
    then raise exception 'permission_denied' using errcode = '42501'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'name', o.data->>'display_name',
    'kind', o.data->>'kind', 'address', coalesce(o.data->>'address',''), 'locationNote', coalesce(o.data->>'location_note',''),
    'addressSource', coalesce(o.data->>'address_source',''), 'mapPlaceId', coalesce(o.data->>'map_place_id',''))
    order by o.data->>'display_name'), '[]'::jsonb)
  into sites from public.hub_objects o
  where o.tenant_id = p_tenant and o.object_type = 'MaterialSite' and o.status = 'active';

  rates := '[]'::jsonb;
  if coalesce(public.hub_has_permission(p_tenant, 'kpi.manage'),false) then
    select coalesce(jsonb_agg(to_jsonb(r) order by r.material, r."validFrom" desc nulls last),'[]'::jsonb)
    into rates from (
      select p.source_key as id, k.object_id as "siteId", 'purchase' as kind, p.material_name as material, p.unit,
        p.net_price as price, p.valid_from as "validFrom", p.valid_to as "validTo", p.source_reference as source, true as imported
      from private.hub_kpi_internal_purchase_prices p
      join public.hub_identity_keys k on k.tenant_id = p.tenant_id and k.identity_value = p.supplier_key
        and k.object_type = 'MaterialSite' and k.identity_type = 'purchase_list_site'
      where p.tenant_id = p_tenant
      union all
      select p.id::text, p.site_id, p.kind, p.material, p.unit, p.price, p.valid_from, p.valid_to, p.source, false
      from private.hub_material_site_rates p where p.tenant_id = p_tenant
    ) r;
  end if;
  return jsonb_build_object('sites', sites, 'rates', rates);
end
$$;

create function private.hub_material_price_bank_save(p_tenant uuid, p_kind text, p_data jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid; selected_site uuid; site_kind text;
  name text := trim(coalesce(p_data->>'name',''));
  label text := trim(coalesce(p_data->>'material',''));
  address text := trim(coalesce(p_data->>'address',''));
begin
  if auth.uid() is null or not coalesce(public.hub_has_permission(p_tenant, 'kpi.manage'),false)
    then raise exception 'permission_denied' using errcode = '42501'; end if;
  if p_data is null or octet_length(p_data::text) > 5000 then raise exception 'invalid_payload'; end if;
  if p_kind = 'site' then
    site_kind := coalesce(p_data->>'kind','');
    if length(name) not between 1 and 120 or length(address) > 240 or length(coalesce(p_data->>'mapPlaceId','')) > 240
      or site_kind not in ('quarry','tip','both') then raise exception 'invalid_site'; end if;
    selected_site := nullif(p_data->>'id','')::uuid;
    perform pg_advisory_xact_lock(hashtextextended(p_tenant::text || ':material-site',0));
    if exists(select 1 from public.hub_objects o where o.tenant_id = p_tenant and o.object_type = 'MaterialSite'
      and o.id is distinct from selected_site and lower(trim(o.data->>'display_name')) = lower(name))
      then raise exception 'duplicate_site' using errcode = '23505'; end if;
    if selected_site is null then
      insert into public.hub_objects (tenant_id, object_type, data, source_of_truth)
      values (p_tenant, 'MaterialSite', jsonb_build_object('display_name', name, 'kind', site_kind, 'address', address,
        'map_place_id', coalesce(p_data->>'mapPlaceId','')), 'humla_price_bank') returning id into result;
    else
      update public.hub_objects o set data = o.data || jsonb_build_object('display_name', name, 'kind', site_kind, 'address', address,
        'map_place_id', coalesce(p_data->>'mapPlaceId',''), 'address_source', case when coalesce(o.data->>'address','') = address
          then coalesce(o.data->>'address_source','') else '' end),
        updated_at = now(), version = version + 1
      where o.id = selected_site and o.tenant_id = p_tenant and o.object_type = 'MaterialSite' and o.status = 'active'
      returning id into result;
    end if;
  elsif p_kind = 'rate' then
    selected_site := (p_data->>'siteId')::uuid;
    select o.data->>'kind' into site_kind from public.hub_objects o where o.id = selected_site
      and o.tenant_id = p_tenant and o.object_type = 'MaterialSite' and o.status = 'active';
    if site_kind is null or p_data->>'kind' = 'purchase' and site_kind = 'tip'
      or p_data->>'kind' = 'tip' and site_kind = 'quarry' then raise exception 'invalid_site'; end if;
    insert into private.hub_material_site_rates (tenant_id, site_id, kind, material, unit, price, valid_from, valid_to, source, created_by)
    values (p_tenant, selected_site, p_data->>'kind', label, p_data->>'unit', (p_data->>'price')::numeric,
      (p_data->>'validFrom')::date, nullif(p_data->>'validTo','')::date, trim(p_data->>'source'), auth.uid())
    returning id into result;
  else raise exception 'invalid_kind'; end if;
  if result is null then raise exception 'site_not_found'; end if;
  return result;
end
$$;

create function public.hub_material_price_bank(p_tenant uuid)
returns jsonb language sql stable security invoker set search_path = '' as
$$ select private.hub_material_price_bank(p_tenant) $$;
create function public.hub_material_price_bank_save(p_tenant uuid, p_kind text, p_data jsonb)
returns uuid language sql security invoker set search_path = '' as
$$ select private.hub_material_price_bank_save(p_tenant, p_kind, p_data) $$;
revoke all on function private.hub_material_price_bank(uuid), private.hub_material_price_bank_save(uuid,text,jsonb),
  public.hub_material_price_bank(uuid), public.hub_material_price_bank_save(uuid,text,jsonb) from public, anon, authenticated;
grant execute on function private.hub_material_price_bank(uuid), private.hub_material_price_bank_save(uuid,text,jsonb),
  public.hub_material_price_bank(uuid), public.hub_material_price_bank_save(uuid,text,jsonb) to authenticated;
