grant insert (tenant_id, created_by, offer_date, fingerprint, customer, project, destinations, materials, offer_pdf, delivery_plan_pdf)
  on public.hub_ton_price_offers to authenticated;

do $policy$
begin
  if not exists(select 1 from pg_policies where schemaname = 'public' and tablename = 'hub_ton_price_offers' and policyname = 'hub_ton_price_offers_insert') then
    create policy hub_ton_price_offers_insert on public.hub_ton_price_offers
      for insert to authenticated with check (
        created_by = (select auth.uid())
        and public.hub_has_permission(tenant_id, 'kpi.manage')
        and offer_date between (created_at at time zone 'Europe/Stockholm')::date - 1
          and (created_at at time zone 'Europe/Stockholm')::date
        and octet_length(offer_pdf) between 6 and 2097152
        and octet_length(delivery_plan_pdf) between 6 and 2097152
        and substring(offer_pdf from 1 for 5) = decode('255044462d','hex')
        and substring(delivery_plan_pdf from 1 for 5) = decode('255044462d','hex')
      );
  end if;
end
$policy$;
