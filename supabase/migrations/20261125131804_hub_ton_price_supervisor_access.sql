create or replace function public.hub_can_use_ton_price(p_tenant_id uuid)
returns boolean language sql stable security invoker set search_path = ''
as $$
  select public.hub_has_permission(p_tenant_id,'ton_price.use')
    or (public.hub_has_permission(p_tenant_id,'kpi.read') and public.hub_has_permission(p_tenant_id,'kpi.manage'));
$$;

CREATE OR REPLACE FUNCTION private.hub_material_price_bank_impl(p_tenant uuid, p_for_ton_price boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sites jsonb; rates jsonb;
begin
  if auth.uid() is null or not (public.hub_has_permission(p_tenant,'kpi.read') or (p_for_ton_price and public.hub_can_use_ton_price(p_tenant)))
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
