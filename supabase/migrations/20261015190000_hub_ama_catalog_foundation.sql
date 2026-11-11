-- Humla Hub: license-aware classification foundation for AMA/BSAB-based budgets.
-- No proprietary code tables or AMA/RA/MER text is supplied by this migration.
create table if not exists public.hub_ama_catalog_entries (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null,
 classification_system text not null check (classification_system in ('AMA','BSAB96')),
 discipline text not null check (discipline in ('ANLAGGNING','HUS','EL','VVS','AF')),
 edition text not null,
 code text not null,
 heading text,
 parent_code text,
 source_name text not null,
 source_reference text,
 usage_rights text not null default 'unverified'
   check (usage_rights in ('unverified','licensed','project_document','own_content')),
 validated_at timestamptz,
 created_at timestamptz not null default now(),
 constraint hub_ama_catalog_entries_unique unique(tenant_id,classification_system,discipline,edition,code)
);
create index if not exists hub_ama_catalog_entries_lookup
 on public.hub_ama_catalog_entries(tenant_id,discipline,edition,code);
alter table public.hub_ama_catalog_entries enable row level security;
create policy hub_ama_catalog_entries_member_read on public.hub_ama_catalog_entries
 for select to authenticated using (
  exists (select 1 from public.hub_tenant_members m
   where m.tenant_id=hub_ama_catalog_entries.tenant_id
     and m.user_id=(select auth.uid()) and m.status='active')
 );
-- Inserts deliberately withheld until the license/import authorization gate exists.
-- Manual creation/import must be handled by a privileged Hub service after rights review.
