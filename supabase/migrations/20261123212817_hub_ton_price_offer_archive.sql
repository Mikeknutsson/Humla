create table if not exists public.hub_ton_price_offers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.hub_tenants(id),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  offer_date date not null,
  fingerprint text not null check (fingerprint ~ '^[0-9a-f]{64}$'),
  customer text not null check (length(customer) <= 240),
  project text not null check (length(project) <= 240),
  destinations text[] not null,
  materials text[] not null check (cardinality(materials) between 1 and 100),
  offer_pdf bytea not null,
  delivery_plan_pdf bytea not null,
  unique (tenant_id, fingerprint)
);

create index if not exists hub_ton_price_offers_archive_idx
  on public.hub_ton_price_offers (tenant_id, created_at desc, id desc);

alter table public.hub_ton_price_offers enable row level security;
revoke all on table public.hub_ton_price_offers from public, anon, authenticated, service_role;
grant select on table public.hub_ton_price_offers to authenticated;
grant select, insert on table public.hub_ton_price_offers to service_role;

do $policy$
begin
  if not exists(select 1 from pg_policies where schemaname = 'public' and tablename = 'hub_ton_price_offers' and policyname = 'hub_ton_price_offers_read') then
    create policy hub_ton_price_offers_read on public.hub_ton_price_offers
      for select to authenticated using (public.hub_has_permission(tenant_id, 'kpi.manage'));
  end if;
end
$policy$;
