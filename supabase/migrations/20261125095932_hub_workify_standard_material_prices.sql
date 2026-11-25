create table public.hub_workify_standard_material_prices (
  tenant_id uuid not null references public.hub_tenants(id),
  article_number text not null check (length(article_number) between 1 and 80),
  article_name text not null check (length(article_name) between 1 and 240),
  material text not null check (length(material) between 1 and 160),
  price numeric(12,4) not null check (price > 0 and price <= 1000000),
  includes_freight boolean not null,
  source_date date not null,
  primary key (tenant_id,article_number)
);

alter table public.hub_workify_standard_material_prices enable row level security;
revoke all on public.hub_workify_standard_material_prices from public, anon, authenticated;
grant select on public.hub_workify_standard_material_prices to authenticated;

create policy hub_workify_standard_material_prices_read on public.hub_workify_standard_material_prices
  for select to authenticated
  using (public.hub_has_permission(tenant_id,'kpi.manage'));
