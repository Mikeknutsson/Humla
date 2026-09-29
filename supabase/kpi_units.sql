-- KPI reporting groups; these do not create or merge canonical Hub identities.
create table public.kpi_units (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.hub_tenants(id),
 name text not null check (length(trim(name)) between 1 and 120),
 unit_type text not null default 'vehicle' check (unit_type in ('vehicle','person','overhead')),
 projects text[] not null default '{}',
 registrations text[] not null default '{}',
 employees text[] not null default '{}',
 valid_from date not null,
 valid_to date,
 enabled boolean not null default true,
 revision integer not null default 1,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check (valid_to is null or valid_to >= valid_from),
 check (cardinality(projects)+cardinality(registrations)+cardinality(employees) between 1 and 300)
);
create index kpi_units_tenant_idx on public.kpi_units(tenant_id);
alter table public.kpi_units enable row level security;
revoke all on public.kpi_units from public, anon;
grant select,insert,update on public.kpi_units to authenticated;
create policy kpi_units_read on public.kpi_units for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.read'));
create policy kpi_units_insert on public.kpi_units for insert to authenticated with check(public.hub_has_permission(tenant_id,'kpi.manage'));
create policy kpi_units_update on public.kpi_units for update to authenticated using(public.hub_has_permission(tenant_id,'kpi.manage')) with check(public.hub_has_permission(tenant_id,'kpi.manage'));

create table public.kpi_unit_events (
 id bigint generated always as identity primary key,
 tenant_id uuid not null references public.hub_tenants(id),
 unit_id uuid not null references public.kpi_units(id),
 actor uuid references auth.users(id),
 previous jsonb,
 current jsonb not null,
 created_at timestamptz not null default now()
);
create index kpi_unit_events_tenant_idx on public.kpi_unit_events(tenant_id);
create index kpi_unit_events_unit_idx on public.kpi_unit_events(unit_id);
create index kpi_unit_events_actor_idx on public.kpi_unit_events(actor);
alter table public.kpi_unit_events enable row level security;
revoke all on public.kpi_unit_events from public,anon,authenticated;
grant select on public.kpi_unit_events to authenticated;
create policy kpi_unit_events_read on public.kpi_unit_events for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.read'));

create function private.kpi_unit_audit() returns trigger language plpgsql security definer set search_path=pg_catalog as $$
begin
 if auth.uid() is null then raise exception 'Authenticated actor required'; end if;
 if tg_op='UPDATE' then
   if new.tenant_id <> old.tenant_id or new.id <> old.id then raise exception 'Immutable ownership'; end if;
   new.revision := old.revision+1;
 else new.revision := 1;
 end if;
 new.updated_at := now();
 return new;
end $$;
create function private.kpi_unit_event() returns trigger language plpgsql security definer set search_path=pg_catalog as $$
begin
 if auth.uid() is null then raise exception 'Authenticated actor required'; end if;
 insert into public.kpi_unit_events(tenant_id,unit_id,actor,previous,current)
 values(new.tenant_id,new.id,auth.uid(),case when tg_op='UPDATE' then to_jsonb(old) else null end,to_jsonb(new));
 return new;
end $$;
revoke all on function private.kpi_unit_audit(),private.kpi_unit_event() from public,anon,authenticated;
create trigger kpi_unit_before before insert or update on public.kpi_units for each row execute function private.kpi_unit_audit();
create trigger kpi_unit_after after insert or update on public.kpi_units for each row execute function private.kpi_unit_event();

create or replace function public.kpi_unit_report(p_tenant_id uuid,p_from date,p_to date)
returns jsonb language sql stable security invoker set search_path=public as $$
with base as (
 select r.*, am.calculation_role mapped_role, am.include_in_vehicle_result,
 case when r.data_kind='cost' then coalesce(am.calculation_role,'unmapped') else r.data_kind end role
 from public.kpi_import_rows r
 join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 left join lateral (
  select m.calculation_role,m.include_in_vehicle_result from public.kpi_account_mappings m
  where r.data_kind='cost' and m.tenant_id=r.tenant_id and m.enabled
   and (case when trim(r.account) ~ '^[0-9]{1,8}$' then trim(r.account)::integer end) between m.account_from and m.account_to
   and r.occurred_on>=m.valid_from and (m.valid_to is null or r.occurred_on<=m.valid_to)
  order by m.priority desc,(m.account_to-m.account_from),m.valid_from desc,m.created_at desc limit 1
 ) am on true
 where r.tenant_id=p_tenant_id and r.occurred_on between p_from and p_to
  and b.status in ('completed','needs_review') and public.hub_has_permission(p_tenant_id,'kpi.read')
), matched as (
 select b.*, hit.ids from base b
 cross join lateral (
  select array_agg(u.id) ids from public.kpi_units u
  where u.tenant_id=b.tenant_id and u.enabled and b.occurred_on>=u.valid_from
   and (u.valid_to is null or b.occurred_on<=u.valid_to)
   and (upper(trim(b.project_reference))=any(u.projects)
     or upper(regexp_replace(b.vehicle_registration,'[[:space:]-]','','g'))=any(u.registrations)
     or upper(trim(b.employee_number))=any(u.employees))
 ) hit
), accepted as (
 select m.*,ids[1] unit_id,u.unit_type from matched m join public.kpi_units u on u.id=m.ids[1] and u.tenant_id=m.tenant_id where cardinality(ids)=1 and is_valid
  and role not in ('unmapped','exclude')
), totals as (
 select unit_id,count(*) row_count,
 coalesce(sum(amount) filter(where role='revenue'),0) revenue,
 coalesce(sum(amount) filter(where role='cost' and (unit_type<>'vehicle' or coalesce(include_in_vehicle_result,true))),0) cost,
 coalesce(sum(amount) filter(where role='fuel' and (unit_type<>'vehicle' or coalesce(include_in_vehicle_result,true))),0) fuel,
 coalesce(sum(paid_hours) filter(where data_kind='driver_time'),0) paid_hours,
 coalesce(sum(billable_hours) filter(where data_kind='driver_time'),0) billable_hours
 from accepted group by unit_id
)
select jsonb_build_object(
 'units',coalesce((select jsonb_agg(to_jsonb(t)||jsonb_build_object('result',t.revenue-t.cost-t.fuel)) from totals t),'[]'::jsonb),
 'quality',jsonb_build_object(
  'conflicts',(select count(*) from matched where cardinality(ids)>1),
  'unassigned',(select count(*) from matched where ids is null),
  'invalid',(select count(*) from matched where not is_valid),
  'unmapped_accounts',(select count(*) from matched where role='unmapped')
 ),
 'conflict_rows',coalesce((select jsonb_agg(to_jsonb(c)) from (
  select batch_id,row_number,project_reference,vehicle_registration,employee_number from matched where cardinality(ids)>1 order by occurred_on,row_number limit 50
 ) c),'[]'::jsonb)
);
$$;
revoke all on function public.kpi_unit_report(uuid,date,date) from public,anon;
grant execute on function public.kpi_unit_report(uuid,date,date) to authenticated;
