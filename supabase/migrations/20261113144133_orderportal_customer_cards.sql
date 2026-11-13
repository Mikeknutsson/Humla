create table public.hub_orderportal_customer_cards (
 tenant_id uuid not null references public.hub_tenants(id),
 customer_id uuid not null references public.hub_objects(id),
 profile jsonb not null check (jsonb_typeof(profile)='object' and octet_length(profile::text)<=50000),
 revision integer not null check (revision>0),
 updated_at timestamptz not null default now(),
 updated_by uuid not null default auth.uid() check (updated_by is not null),
 primary key (tenant_id,customer_id)
);

alter table public.hub_orderportal_customer_cards enable row level security;
revoke all on public.hub_orderportal_customer_cards from public,anon,authenticated;
grant select,insert on public.hub_orderportal_customer_cards to authenticated;
grant update (profile,revision,updated_at,updated_by) on public.hub_orderportal_customer_cards to authenticated;

create policy orderportal_customer_cards_select on public.hub_orderportal_customer_cards
 for select to authenticated using (public.hub_has_permission(tenant_id,'kpi.manage'));

create policy orderportal_customer_cards_insert on public.hub_orderportal_customer_cards
 for insert to authenticated with check (
  updated_by=(select auth.uid()) and public.hub_has_permission(tenant_id,'kpi.manage')
  and exists(select 1 from public.hub_objects o where o.id=customer_id
   and o.tenant_id=hub_orderportal_customer_cards.tenant_id and o.object_type='Customer' and o.status='active')
 );

create policy orderportal_customer_cards_update on public.hub_orderportal_customer_cards
 for update to authenticated using (public.hub_has_permission(tenant_id,'kpi.manage'))
 with check (
  updated_by=(select auth.uid()) and public.hub_has_permission(tenant_id,'kpi.manage')
  and exists(select 1 from public.hub_objects o where o.id=customer_id
   and o.tenant_id=hub_orderportal_customer_cards.tenant_id and o.object_type='Customer' and o.status='active')
 );
