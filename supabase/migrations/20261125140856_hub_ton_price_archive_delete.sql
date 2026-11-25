create index hub_ton_price_offers_source_idx
  on public.hub_ton_price_offers (tenant_id, source_offer_id)
  where source_offer_id is not null;

grant delete on public.hub_ton_price_offers to authenticated;

create policy hub_ton_price_offers_delete on public.hub_ton_price_offers
  for delete to authenticated using (
    public.hub_can_use_ton_price(tenant_id)
    and (public.hub_has_permission(tenant_id,'kpi.manage') or created_by = (select auth.uid()))
  );
