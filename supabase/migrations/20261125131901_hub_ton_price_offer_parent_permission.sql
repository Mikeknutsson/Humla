create function private.hub_ton_price_can_reference_offer(p_tenant uuid,p_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.hub_can_use_ton_price(p_tenant) and exists (
    select 1 from public.hub_ton_price_offers o
    where o.tenant_id = p_tenant and o.id = p_id
      and (o.created_by = (select auth.uid()) or public.hub_has_permission(p_tenant,'kpi.manage'))
  )
$$;
revoke all on function private.hub_ton_price_can_reference_offer(uuid,uuid) from public,anon;
grant execute on function private.hub_ton_price_can_reference_offer(uuid,uuid) to authenticated;

alter policy hub_ton_price_offers_insert on public.hub_ton_price_offers with check (
  created_by = (select auth.uid())
  and public.hub_can_use_ton_price(tenant_id)
  and (source_offer_id is null or private.hub_ton_price_can_reference_offer(tenant_id,source_offer_id))
  and offer_date between (created_at at time zone 'Europe/Stockholm')::date - 1
    and (created_at at time zone 'Europe/Stockholm')::date
  and octet_length(offer_pdf) between 6 and 2097152
  and octet_length(delivery_plan_pdf) between 6 and 2097152
  and substring(offer_pdf from 1 for 5) = decode('255044462d','hex')
  and substring(delivery_plan_pdf from 1 for 5) = decode('255044462d','hex')
);
