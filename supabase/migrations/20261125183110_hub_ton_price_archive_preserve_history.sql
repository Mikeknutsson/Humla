create policy hub_ton_price_offers_preserve_history on public.hub_ton_price_offers
  as restrictive for delete to authenticated using (false);
