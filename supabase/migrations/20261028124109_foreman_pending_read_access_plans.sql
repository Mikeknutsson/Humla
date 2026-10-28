create table private.hub_foreman_access_plans(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,
 email text not null check(email=lower(email)),display_name text not null,
 access_mode text not null default 'read_only' check(access_mode='read_only'),
 requested_groups text[] not null,
 status text not null default 'awaiting_activation' check(status in ('awaiting_activation','active','closed')),
 include_descendants boolean not null default true,
 allow_login_delivery boolean not null default false,
 approved_by uuid not null,approved_at timestamptz not null default now(),
 evidence text not null,unique(tenant_id,email)
);
create table private.hub_foreman_access_plan_units(
 plan_id uuid not null references private.hub_foreman_access_plans(id),
 unit_id uuid not null references public.hub_objects(id),
 basis text not null,primary key(plan_id,unit_id)
);
alter table private.hub_foreman_access_plans enable row level security;
alter table private.hub_foreman_access_plan_units enable row level security;
revoke all on private.hub_foreman_access_plans,private.hub_foreman_access_plan_units from public,anon,authenticated;
comment on table private.hub_foreman_access_plans is 'Owner-approved pending access configuration, not an identity registry or an active authorization grant. Resolve canonical units and bind a verified account before activation.';