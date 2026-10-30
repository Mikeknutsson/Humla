-- Canonical, owner-confirmed account links; no source-system identity is used as a user identity.
create table if not exists private.hub_driver_account_links (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,user_id uuid not null,
 person_object_id uuid not null references public.hub_objects(id),
 valid_from timestamptz not null default now(),valid_to timestamptz,
 confirmed_by uuid not null references auth.users(id),
 foreign key(tenant_id,user_id) references public.hub_tenant_members(tenant_id,user_id),
 check(valid_to is null or valid_to>=valid_from)
);
create unique index if not exists hub_driver_account_active_user on private.hub_driver_account_links(tenant_id,user_id) where valid_to is null;
create unique index if not exists hub_driver_account_active_person on private.hub_driver_account_links(tenant_id,person_object_id) where valid_to is null;
alter table private.hub_driver_account_links enable row level security;
revoke all on private.hub_driver_account_links from public,anon,authenticated;

create or replace function private.hub_driver_directory_v1(p_tenant uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.hub_tenant_members where tenant_id=p_tenant and user_id=auth.uid() and role='owner' and status='active') then raise exception 'Forbidden' using errcode='42501';end if;
 return jsonb_build_object(
 'people',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'name',coalesce(nullif(o.data->>'display_name',''),o.data->>'name','Chaufför'),'linked_user',l.user_id) order by coalesce(o.data->>'display_name',o.data->>'name')),'[]')
 from public.hub_objects o left join private.hub_driver_account_links l on l.tenant_id=o.tenant_id and l.person_object_id=o.id and l.valid_to is null
 where o.tenant_id=p_tenant and o.object_type='Person' and o.status='active' and exists(select 1 from public.hub_identity_keys k where k.tenant_id=o.tenant_id and k.object_id=o.id and k.identity_type='transpa_employee_id' and k.confidence=1)),
 'accounts',(select coalesce(jsonb_agg(jsonb_build_object('id',user_id,'name',coalesce(display_name,'Chaufförskonto')) order by display_name),'[]') from public.hub_tenant_members where tenant_id=p_tenant and role='worker' and status='active'));
end $$;

create or replace function private.hub_driver_bind_account_v1(p_tenant uuid,p_user uuid,p_person uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.hub_tenant_members where tenant_id=p_tenant and user_id=auth.uid() and role='owner' and status='active') then raise exception 'Forbidden' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant::text,0));
 if not exists(select 1 from public.hub_tenant_members where tenant_id=p_tenant and user_id=p_user and role='worker' and status='active') then raise exception 'Active worker account required';end if;
 if p_person is not null and not exists(select 1 from public.hub_objects o where o.id=p_person and o.tenant_id=p_tenant and o.object_type='Person' and o.status='active' and exists(select 1 from public.hub_identity_keys k where k.tenant_id=o.tenant_id and k.object_id=o.id and k.identity_type='transpa_employee_id' and k.confidence=1)) then raise exception 'Canonical driver required';end if;
 if exists(select 1 from private.hub_driver_account_links where tenant_id=p_tenant and user_id=p_user and person_object_id=p_person and valid_to is null) then return;end if;
 if p_person is not null and exists(select 1 from private.hub_driver_account_links where tenant_id=p_tenant and person_object_id=p_person and user_id<>p_user and valid_to is null) then raise exception 'Person already linked';end if;
 update private.hub_driver_account_links set valid_to=now() where tenant_id=p_tenant and user_id=p_user and valid_to is null;
 if p_person is not null then insert into private.hub_driver_account_links(tenant_id,user_id,person_object_id,confirmed_by) values(p_tenant,p_user,p_person,auth.uid());end if;
end $$;

-- Returns only qualitative feedback. No amounts, salary, customer, order, or colleague data.
create or replace function private.hub_driver_self_v1(p_tenant uuid,p_from date,p_to date,p_person uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='10s' as $$
declare person uuid; member_role text; output jsonb; today date:=(now() at time zone 'Europe/Stockholm')::date;
begin
 select role into member_role from public.hub_tenant_members where tenant_id=p_tenant and user_id=auth.uid() and status='active';
 if auth.uid() is null or member_role is null then raise exception 'Forbidden' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to>today or p_to-p_from>62 then raise exception 'Invalid period';end if;
 if p_person is not null then
  if member_role<>'owner' then raise exception 'Forbidden' using errcode='42501';end if;person:=p_person;
 else
  select person_object_id into person from private.hub_driver_account_links where tenant_id=p_tenant and user_id=auth.uid() and valid_from<=now() and valid_to is null;
 end if;
 if person is null then return jsonb_build_object('status','unlinked');end if;
 if not exists(select 1 from public.hub_objects where id=person and tenant_id=p_tenant and object_type='Person' and status='active') then raise exception 'Forbidden' using errcode='42501';end if;
 with time_rows as materialized(
  select t.work_date,t.report_status,t.work_hours,
   case when jsonb_typeof(t.transpa_vehicle_ids)='array' then jsonb_array_length(t.transpa_vehicle_ids)=1 else false end vehicle_linked
  from public.kpi_transpa_time_facts t
  where t.tenant_id=p_tenant and t.work_date between p_from-(p_to-p_from+1) and p_to and t.work_hours>0
   and (t.person_object_id=person or (t.person_object_id is null and exists(
    select 1 from public.hub_identity_keys k where k.tenant_id=p_tenant and k.object_id=person and k.identity_type='transpa_employee_id' and k.confidence=1 and k.identity_value=t.employee_id
    and not exists(select 1 from public.hub_identity_keys other where other.tenant_id=k.tenant_id and other.identity_type=k.identity_type and other.identity_value=k.identity_value and other.object_id<>person))))
 ),stats as(select count(*) filter(where work_date>=p_from) n,
 count(*) filter(where work_date>=p_from and report_status not in ('approved','submitted')) pending,
 count(*) filter(where work_date>=p_from and report_status is null) unknown,
 sum(work_hours)filter(where work_date>=p_from) hours,
 sum(work_hours)filter(where work_date>=p_from and vehicle_linked) vehicle_hours,
 sum(work_hours)filter(where work_date<p_from) old_hours,
 sum(work_hours)filter(where work_date<p_from and vehicle_linked) old_vehicle_hours,
 max(work_date)filter(where work_date>=p_from) latest from time_rows),
 ratios as(select *,coalesce(vehicle_hours,0)/nullif(hours,0) share,coalesce(old_vehicle_hours,0)/nullif(old_hours,0) old_share from stats),
 weeks as(select d::date week_from,least(d::date+6,p_to) week_to from generate_series(p_from,p_to,interval '7 days') d),
 week_stats as(select w.week_from,w.week_to,count(t.work_date) n,
 coalesce(sum(t.work_hours)filter(where t.vehicle_linked),0)/nullif(sum(t.work_hours),0) share
 from weeks w left join time_rows t on t.work_date between w.week_from and w.week_to group by 1,2)
 select jsonb_build_object('status','ready','name',(select coalesce(nullif(data->>'display_name',''),data->>'name','Chaufför') from public.hub_objects where id=person and tenant_id=p_tenant),
 'from',p_from,'to',p_to,'latest_work_date',latest,
 'reporting',case when n=0 then 'unknown' when pending>0 then 'attention' when unknown>0 then 'unknown' else 'good' end,
 'vehicle_link',case when n=0 then 'unknown' when share>=0.9 then 'good' when share>=0.5 then 'partial' else 'attention' end,
 'trend',case when hours is null or old_hours is null then 'unknown' when share-old_share>0.05 then 'up' when share-old_share< -0.05 then 'down' else 'steady' end,
 'weeks',(select coalesce(jsonb_agg(jsonb_build_object('from',week_from,'to',week_to,'band',case when n=0 then null when share>=0.9 then 4 when share>=0.75 then 3 when share>=0.5 then 2 else 1 end) order by week_from),'[]') from week_stats),
 'vehicle_economy','unknown','fuel','unknown') into output from ratios;
 return output;
end $$;
revoke all on function private.hub_driver_directory_v1(uuid) from public,anon;
revoke all on function private.hub_driver_bind_account_v1(uuid,uuid,uuid) from public,anon;
revoke all on function private.hub_driver_self_v1(uuid,date,date,uuid) from public,anon;
grant execute on function private.hub_driver_directory_v1(uuid) to authenticated;
grant execute on function private.hub_driver_bind_account_v1(uuid,uuid,uuid) to authenticated;
grant execute on function private.hub_driver_self_v1(uuid,date,date,uuid) to authenticated;
create or replace function public.hub_driver_directory_v1(p_tenant uuid) returns jsonb
 language sql stable security invoker set search_path='' as $$select private.hub_driver_directory_v1(p_tenant)$$;
create or replace function public.hub_driver_bind_account_v1(p_tenant uuid,p_user uuid,p_person uuid) returns void
 language sql security invoker set search_path='' as $$select private.hub_driver_bind_account_v1(p_tenant,p_user,p_person)$$;
create or replace function public.hub_driver_self_v1(p_tenant uuid,p_from date,p_to date,p_person uuid default null) returns jsonb
 language sql stable security invoker set search_path='' as $$select private.hub_driver_self_v1(p_tenant,p_from,p_to,p_person)$$;
revoke all on function public.hub_driver_directory_v1(uuid) from public,anon;
revoke all on function public.hub_driver_bind_account_v1(uuid,uuid,uuid) from public,anon;
revoke all on function public.hub_driver_self_v1(uuid,date,date,uuid) from public,anon;
grant execute on function public.hub_driver_directory_v1(uuid) to authenticated;
grant execute on function public.hub_driver_bind_account_v1(uuid,uuid,uuid) to authenticated;
grant execute on function public.hub_driver_self_v1(uuid,date,date,uuid) to authenticated;

