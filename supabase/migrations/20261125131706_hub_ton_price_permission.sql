insert into public.hub_permissions (code,name,description)
values ('ton_price.use','Tonpriskalkyl','Beräkna tonpriser och skapa, läsa och komplettera egna offerter.')
on conflict (code) do nothing;

create function public.hub_can_use_ton_price(p_tenant_id uuid)
returns boolean language sql stable security invoker set search_path = ''
as $$
  select public.hub_has_permission(p_tenant_id,'kpi.read')
    and (public.hub_has_permission(p_tenant_id,'kpi.manage') or public.hub_has_permission(p_tenant_id,'ton_price.use'));
$$;
revoke all on function public.hub_can_use_ton_price(uuid) from public, anon;
grant execute on function public.hub_can_use_ton_price(uuid) to authenticated;

CREATE OR REPLACE FUNCTION private.hub_material_price_bank_impl(p_tenant uuid, p_for_ton_price boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if coalesce(public.hub_has_permission(p_tenant, 'kpi.manage'),false)
    or (p_for_ton_price and public.hub_has_permission(p_tenant, 'ton_price.use')) then
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
$function$;
revoke all on function private.hub_material_price_bank_impl(uuid,boolean) from public,anon,authenticated;
grant execute on function private.hub_material_price_bank_impl(uuid,boolean) to authenticated;

create or replace function private.hub_material_price_bank(p_tenant uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.hub_material_price_bank_impl(p_tenant,false) $$;

create function public.hub_ton_price_material_bank(p_tenant uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$
  select private.hub_material_price_bank_impl(p_tenant,true)
  where public.hub_can_use_ton_price(p_tenant)
$$;
revoke all on function public.hub_ton_price_material_bank(uuid) from public,anon;
grant execute on function public.hub_ton_price_material_bank(uuid) to authenticated;

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
    and (select public.hub_can_use_ton_price(p_tenant_id))
    and r.data_kind = 'revenue' and r.is_valid
    and b.status in ('completed', 'needs_review')
    and (r.source_system = 'workify_file' or
      (r.source_system is null and r.source_data ?& array['Ordernummer','Artikelnummer','Artikeldatum']))
    and length(customer.name) between 1 and 240
  group by lower(customer.name)
  order by lower(customer.name);
$function$;
revoke all on function private.hub_ton_price_workify_customers(uuid) from public,anon;
grant execute on function private.hub_ton_price_workify_customers(uuid) to authenticated;
create or replace function public.hub_ton_price_workify_customers(p_tenant_id uuid)
returns table(name text) language sql stable security invoker set search_path = ''
as $$ select * from private.hub_ton_price_workify_customers(p_tenant_id) $$;

create policy hub_workify_standard_material_prices_quote_read on public.hub_workify_standard_material_prices
  for select to authenticated using (public.hub_can_use_ton_price(tenant_id));

create policy hub_ton_price_offers_read_own on public.hub_ton_price_offers
  for select to authenticated using (
    created_by = (select auth.uid()) and public.hub_can_use_ton_price(tenant_id)
  );

alter policy hub_ton_price_offers_insert on public.hub_ton_price_offers with check (
  created_by = (select auth.uid())
  and public.hub_can_use_ton_price(tenant_id)
  and (source_offer_id is null or exists (
    select 1 from public.hub_ton_price_offers parent
    where parent.tenant_id = hub_ton_price_offers.tenant_id and parent.id = hub_ton_price_offers.source_offer_id
  ))
  and offer_date between (created_at at time zone 'Europe/Stockholm')::date - 1
    and (created_at at time zone 'Europe/Stockholm')::date
  and octet_length(offer_pdf) between 6 and 2097152
  and octet_length(delivery_plan_pdf) between 6 and 2097152
  and substring(offer_pdf from 1 for 5) = decode('255044462d','hex')
  and substring(delivery_plan_pdf from 1 for 5) = decode('255044462d','hex')
);
