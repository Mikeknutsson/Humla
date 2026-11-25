alter table public.hub_ton_price_offers
  add column calculation_snapshot jsonb,
  add column source_offer_id uuid,
  add constraint hub_ton_price_offers_tenant_id_id_key unique (tenant_id, id),
  add constraint hub_ton_price_offers_source_offer_fk foreign key (tenant_id, source_offer_id)
    references public.hub_ton_price_offers (tenant_id, id),
  add constraint hub_ton_price_offers_source_is_distinct check (source_offer_id is distinct from id),
  add constraint hub_ton_price_offers_snapshot_valid check (
    calculation_snapshot is null or (
      jsonb_typeof(calculation_snapshot) = 'object' and octet_length(calculation_snapshot::text) <= 524288
    )
  );

grant insert (source_offer_id, calculation_snapshot) on public.hub_ton_price_offers to authenticated;
