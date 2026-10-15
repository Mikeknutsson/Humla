-- Assign a leader to canonical KPI economic units without exposing other leaders' data.
-- No automatic grants: assignments must be explicitly reviewed by an owner.
create table if not exists public.hub_transport_leader_units (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null,
 user_id uuid not null,
 unit_id uuid not null references public.kpi_units(id) on delete cascade,
 valid_from date not null default current_date,
 valid_to date,
 assigned_by uuid,
 created_at timestamptz not null default now(),
 unique(tenant_id,user_id,unit_id,valid_from),
 constraint hub_transport_leader_units_dates check (valid_to is null or valid_to>=valid_from)
);
create index if not exists hub_transport_leader_units_lookup on public.hub_transport_leader_units(tenant_id,user_id,valid_from,valid_to);
alter table public.hub_transport_leader_units enable row level security;
create policy hub_transport_leader_units_read on public.hub_transport_leader_units
 for select to authenticated using (
  exists(select 1 from public.hub_tenant_members m where m.tenant_id=hub_transport_leader_units.tenant_id
  and m.user_id=(select auth.uid()) and m.status='active'
  and (m.role='owner' or hub_transport_leader_units.user_id=(select auth.uid())))
 );
create policy hub_transport_leader_units_owner_insert on public.hub_transport_leader_units
 for insert to authenticated with check (
  exists(select 1 from public.hub_tenant_members m where m.tenant_id=hub_transport_leader_units.tenant_id
  and m.user_id=(select auth.uid()) and m.status='active' and m.role='owner')
  and exists(select 1 from public.hub_tenant_members m where m.tenant_id=hub_transport_leader_units.tenant_id
  and m.user_id=hub_transport_leader_units.user_id and m.status='active')
  and exists(select 1 from public.kpi_units u where u.tenant_id=hub_transport_leader_units.tenant_id and u.id=hub_transport_leader_units.unit_id)
 );
create policy hub_transport_leader_units_owner_update on public.hub_transport_leader_units
 for update to authenticated using (
  exists(select 1 from public.hub_tenant_members m where m.tenant_id=hub_transport_leader_units.tenant_id
  and m.user_id=(select auth.uid()) and m.status='active' and m.role='owner')
 ) with check (
  exists(select 1 from public.hub_tenant_members m where m.tenant_id=hub_transport_leader_units.tenant_id
  and m.user_id=(select auth.uid()) and m.status='active' and m.role='owner')
 );
create policy hub_transport_leader_units_owner_delete on public.hub_transport_leader_units
 for delete to authenticated using (
  exists(select 1 from public.hub_tenant_members m where m.tenant_id=hub_transport_leader_units.tenant_id
  and m.user_id=(select auth.uid()) and m.status='active' and m.role='owner')
 );
-- Explicit lookup RPC: never accept arbitrary tenant/user for a non-owner.
create or replace function public.hub_transport_leader_units_for_user(p_tenant_id uuid,p_user_id uuid default null,p_as_of date default current_date)
returns table(unit_id uuid,unit_name text,unit_type text,registrations text[])
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid();v_owner boolean;v_target uuid;
begin
 if v_user is null or not exists(select 1 from public.hub_tenant_members m
  where m.tenant_id=p_tenant_id and m.user_id=v_user and m.status='active') then
  raise exception 'access_denied' using errcode='42501';
 end if;
 select exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant_id
  and m.user_id=v_user and m.status='active' and m.role='owner') into v_owner;
 v_target:=coalesce(p_user_id,v_user);
 if v_target<>v_user and not v_owner then raise exception 'access_denied' using errcode='42501'; end if;
 if not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant_id
  and m.user_id=v_target and m.status='active') then
  raise exception 'access_denied' using errcode='42501';
 end if;
 return query
 select u.id,u.name,u.unit_type,u.registrations
 from public.hub_transport_leader_units a join public.kpi_units u on u.id=a.unit_id and u.tenant_id=a.tenant_id
 where a.tenant_id=p_tenant_id and a.user_id=v_target and a.valid_from<=p_as_of
 and (a.valid_to is null or a.valid_to>=p_as_of) and u.enabled
 order by u.name;
end $$;
revoke all on function public.hub_transport_leader_units_for_user(uuid,uuid,date) from public;
grant execute on function public.hub_transport_leader_units_for_user(uuid,uuid,date) to authenticated;
