create table if not exists public.kpi_attendance_settings(tenant_id uuid primary key references public.hub_tenants(id),timezone text not null default 'Europe/Stockholm',start_time time not null default '07:00',end_time time not null default '16:00',break_minutes integer not null default 60 check(break_minutes between 0 and 480),weekdays integer[] not null default array[1,2,3,4,5],exclude_public_holidays boolean not null default true,updated_by uuid default auth.uid(),updated_at timestamptz not null default now());
alter table public.kpi_attendance_settings enable row level security;
create policy attendance_settings_read on public.kpi_attendance_settings for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.read'));
create policy attendance_settings_manage on public.kpi_attendance_settings for all to authenticated using(public.hub_has_permission(tenant_id,'kpi.manage')) with check(public.hub_has_permission(tenant_id,'kpi.manage'));
grant select,insert,update on public.kpi_attendance_settings to authenticated;revoke all on public.kpi_attendance_settings from anon;
create table if not exists public.kpi_transpa_attendance_codes(tenant_id uuid not null references public.hub_tenants(id),pay_type_code text not null,category text not null check(category in ('worked','sick','vab','vacation','other')),unit text not null check(unit in ('hours','days')),updated_by uuid not null default auth.uid(),updated_at timestamptz not null default now(),primary key(tenant_id,pay_type_code));
alter table public.kpi_transpa_attendance_codes enable row level security;
create policy attendance_codes_read on public.kpi_transpa_attendance_codes for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.read'));
create policy attendance_codes_manage on public.kpi_transpa_attendance_codes for all to authenticated using(public.hub_has_permission(tenant_id,'kpi.manage')) with check(public.hub_has_permission(tenant_id,'kpi.manage'));
grant select,insert,update on public.kpi_transpa_attendance_codes to authenticated;revoke all on public.kpi_transpa_attendance_codes from anon;
insert into public.kpi_attendance_settings(tenant_id,start_time,end_time,break_minutes,weekdays) select id,'07:00','16:00',60,array[1,2,3,4,5] from public.hub_tenants where id='944597b6-9c46-4bef-998d-f19e23c4245b' on conflict(tenant_id) do update set start_time=excluded.start_time,end_time=excluded.end_time,break_minutes=excluded.break_minutes,weekdays=excluded.weekdays,updated_at=now();
create or replace function private.hub_transpa_salary_queue_tick_v1() returns jsonb language plpgsql security definer set search_path='' as $f$
declare ev record; requests integer:=0; secret text;
begin
 select decrypted_secret into secret from vault.decrypted_secrets where name='humla_worker_key' limit 1;
 if coalesce(secret,'')='' then return jsonb_build_object('queued',0);end if;
 for ev in select id from public.hub_transpa_salary_events where (status in ('pending','retry') and coalesce(next_attempt_at,'-infinity'::timestamptz)<=now()) or (status='processing' and updated_at<now()-interval '10 minutes') order by received_at limit 5 for update skip locked loop
 update public.hub_transpa_salary_events set status='processing',updated_at=now(),next_attempt_at=now()+interval '10 minutes' where id=ev.id;
 perform net.http_post(url:='https://vuurtaafxvevbhdzgttq.supabase.co/functions/v1/transpa-salary-fetch',headers:=jsonb_build_object('Content-Type','application/json','x-humla-worker-key',secret),body:=jsonb_build_object('event_id',ev.id),timeout_milliseconds:=120000);requests:=requests+1;
 end loop;
 return jsonb_build_object('queued',requests);
end $f$;
revoke all on function private.hub_transpa_salary_queue_tick_v1() from public,anon,authenticated;
select cron.schedule('humla-transpa-salary-events','*/5 * * * *','select private.hub_transpa_salary_queue_tick_v1();');
