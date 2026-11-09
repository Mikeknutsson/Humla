create table if not exists public.hub_allocation_mapping_rules (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null,
 dimension text not null check (dimension in ('cost_center','project','vehicle')),
 evidence_type text not null check (evidence_type in ('project','supervisor','driver','customer','supplier','account','article','reference','vehicle_registration')),
 evidence_value text not null check (length(trim(evidence_value))>0),
 target_value text not null check (length(trim(target_value))>0),
 valid_from date,
 valid_to date,
 confidence numeric(5,4) not null default 1 check (confidence between 0 and 1),
 rule_status text not null default 'confirmed' check(rule_status in ('confirmed','disabled')),
 source text not null default 'manual',
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint hub_mapping_valid_dates check(valid_to is null or valid_from is null or valid_to>=valid_from)
);
create index if not exists hub_allocation_mapping_rules_lookup on public.hub_allocation_mapping_rules(tenant_id,dimension,evidence_type,upper(trim(evidence_value))) where rule_status='confirmed';
alter table public.hub_allocation_mapping_rules enable row level security;
create policy hub_allocation_mapping_rules_read on public.hub_allocation_mapping_rules for select to authenticated using (public.hub_has_permission(tenant_id,'kpi.manage'));
create policy hub_allocation_mapping_rules_insert on public.hub_allocation_mapping_rules for insert to authenticated with check (public.hub_has_permission(tenant_id,'kpi.manage'));
create policy hub_allocation_mapping_rules_update on public.hub_allocation_mapping_rules for update to authenticated using (public.hub_has_permission(tenant_id,'kpi.manage')) with check (public.hub_has_permission(tenant_id,'kpi.manage'));
revoke all on public.hub_allocation_mapping_rules from anon;
grant select,insert,update on public.hub_allocation_mapping_rules to authenticated;
