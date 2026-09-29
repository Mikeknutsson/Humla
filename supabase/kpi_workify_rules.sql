-- Versioned source register. Blank project explicitly allocates to executing vehicle.
create table public.kpi_workify_article_rules (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.hub_tenants(id),
 article_number text not null,
 project_reference text,
 cost_center text,
 source_file text not null,
 source_hash text not null,
 source_rows jsonb not null,
 enabled boolean not null default true,
 created_at timestamptz not null default now(),
 unique(tenant_id,article_number,source_hash)
);
create unique index kpi_workify_active_article on public.kpi_workify_article_rules(tenant_id,article_number) where enabled;
alter table public.kpi_workify_article_rules enable row level security;
revoke all on public.kpi_workify_article_rules from public,anon,authenticated;
grant select on public.kpi_workify_article_rules to authenticated;
create policy kpi_workify_read on public.kpi_workify_article_rules for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.read'));
alter table public.kpi_import_rows add column allocation jsonb;
