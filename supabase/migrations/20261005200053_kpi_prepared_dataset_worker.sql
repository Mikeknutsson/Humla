-- Isolated Dashboard report preparation. Raw Hub data and integration sync jobs are untouched.
create table private.hub_kpi_report_generations(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.hub_tenants(id),
 created_at timestamptz not null default now(), completed_at timestamptz,
 first_fiscal_year integer not null, last_fiscal_year integer not null);
create table private.hub_kpi_report_state(
 tenant_id uuid primary key references public.hub_tenants(id), active_generation uuid references private.hub_kpi_report_generations(id),
 synced_at timestamptz, status text not null default 'queued' check(status in ('queued','ready','failed')),
 requested_at timestamptz not null default now(), requested_by uuid not null references auth.users(id),
 last_nightly_date date, error_code text);
create table private.hub_kpi_prepared_facts(
 generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, tenant_id uuid not null,
 fiscal_year integer not null,
 fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text,
 unit_id uuid, unit_name text, business_group text, source text, description text, account text,
 file_name text, row_number integer, original jsonb, cost_center text, cost_center_name text, classification_source jsonb);
create index on private.hub_kpi_prepared_facts(generation_id,fiscal_year,occurred_on);
create index on private.hub_kpi_prepared_facts(generation_id,fiscal_year,cost_center,business_group);
create index on private.hub_kpi_prepared_facts(generation_id,unit_id,vehicle);
create table private.hub_kpi_prepared_daily(
 generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade,
 tenant_id uuid,work_date date,vehicle_id text,vehicle_name text,reported_vehicle_hours numeric,time_reports bigint);
create index on private.hub_kpi_prepared_daily(generation_id,work_date);
create table private.hub_kpi_prepared_hub_objects (generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, like public.hub_objects);
alter table private.hub_kpi_prepared_hub_objects enable row level security;
revoke all on private.hub_kpi_prepared_hub_objects from public, anon, authenticated;
create index on private.hub_kpi_prepared_hub_objects(generation_id,tenant_id);
create table private.hub_kpi_prepared_hub_transpa_entities (generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, like public.hub_transpa_entities);
alter table private.hub_kpi_prepared_hub_transpa_entities enable row level security;
revoke all on private.hub_kpi_prepared_hub_transpa_entities from public, anon, authenticated;
create index on private.hub_kpi_prepared_hub_transpa_entities(generation_id,tenant_id);
create table private.hub_kpi_prepared_hub_vehicle_meter_readings (generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, like public.hub_vehicle_meter_readings);
alter table private.hub_kpi_prepared_hub_vehicle_meter_readings enable row level security;
revoke all on private.hub_kpi_prepared_hub_vehicle_meter_readings from public, anon, authenticated;
create index on private.hub_kpi_prepared_hub_vehicle_meter_readings(generation_id,tenant_id);
create table private.hub_kpi_prepared_kpi_business_groups (generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, like public.kpi_business_groups);
alter table private.hub_kpi_prepared_kpi_business_groups enable row level security;
revoke all on private.hub_kpi_prepared_kpi_business_groups from public, anon, authenticated;
create index on private.hub_kpi_prepared_kpi_business_groups(generation_id,tenant_id);
create table private.hub_kpi_prepared_kpi_import_rows (generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, like public.kpi_import_rows);
alter table private.hub_kpi_prepared_kpi_import_rows enable row level security;
revoke all on private.hub_kpi_prepared_kpi_import_rows from public, anon, authenticated;
create index on private.hub_kpi_prepared_kpi_import_rows(generation_id,tenant_id);
create table private.hub_kpi_prepared_kpi_project_classification_periods (generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, like public.kpi_project_classification_periods);
alter table private.hub_kpi_prepared_kpi_project_classification_periods enable row level security;
revoke all on private.hub_kpi_prepared_kpi_project_classification_periods from public, anon, authenticated;
create index on private.hub_kpi_prepared_kpi_project_classification_periods(generation_id,tenant_id);
create table private.hub_kpi_prepared_kpi_settings (generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, like public.kpi_settings);
alter table private.hub_kpi_prepared_kpi_settings enable row level security;
revoke all on private.hub_kpi_prepared_kpi_settings from public, anon, authenticated;
create index on private.hub_kpi_prepared_kpi_settings(generation_id,tenant_id);
create table private.hub_kpi_prepared_kpi_transpa_time_facts (generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, like public.kpi_transpa_time_facts);
alter table private.hub_kpi_prepared_kpi_transpa_time_facts enable row level security;
revoke all on private.hub_kpi_prepared_kpi_transpa_time_facts from public, anon, authenticated;
create index on private.hub_kpi_prepared_kpi_transpa_time_facts(generation_id,tenant_id);
create table private.hub_kpi_prepared_kpi_unit_periods (generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, like public.kpi_unit_periods);
alter table private.hub_kpi_prepared_kpi_unit_periods enable row level security;
revoke all on private.hub_kpi_prepared_kpi_unit_periods from public, anon, authenticated;
create index on private.hub_kpi_prepared_kpi_unit_periods(generation_id,tenant_id);
create table private.hub_kpi_prepared_kpi_units (generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, like public.kpi_units);
alter table private.hub_kpi_prepared_kpi_units enable row level security;
revoke all on private.hub_kpi_prepared_kpi_units from public, anon, authenticated;
create index on private.hub_kpi_prepared_kpi_units(generation_id,tenant_id);
create table private.hub_kpi_prepared_kpi_vehicle_distance_periods (generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, like public.kpi_vehicle_distance_periods);
alter table private.hub_kpi_prepared_kpi_vehicle_distance_periods enable row level security;
revoke all on private.hub_kpi_prepared_kpi_vehicle_distance_periods from public, anon, authenticated;
create index on private.hub_kpi_prepared_kpi_vehicle_distance_periods(generation_id,tenant_id);
create index on private.hub_kpi_prepared_kpi_transpa_time_facts(generation_id,work_date);
create index on private.hub_kpi_prepared_hub_vehicle_meter_readings(generation_id,tenant_id,vehicle_id,reading_type,recorded_at);
do $security$
declare t text;
begin
 foreach t in array array['hub_kpi_report_generations','hub_kpi_report_state','hub_kpi_prepared_facts','hub_kpi_prepared_daily'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;
end $security$;

create function private.hub_kpi_report_status_v1(p_tenant_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $fn$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 select jsonb_build_object('generation',active_generation,'synced_at',synced_at,'status',status,
 'requested_at',requested_at,'can_sync',public.hub_has_permission(p_tenant_id,'kpi.manage'),
 'error',case when status='failed' then 'Synkningen misslyckades. Senaste fungerande underlaget visas.' end,
 'schedule','03:00 Europe/Stockholm') into result from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 return coalesce(result,jsonb_build_object('status','unavailable','generation',null,'synced_at',null,
 'can_sync',public.hub_has_permission(p_tenant_id,'kpi.manage'),'schedule','03:00 Europe/Stockholm'));
end $fn$;
revoke all on function private.hub_kpi_report_status_v1(uuid) from public,anon;
grant execute on function private.hub_kpi_report_status_v1(uuid) to authenticated;
create function public.hub_kpi_report_status_v1(p_tenant_id uuid) returns jsonb
language sql stable set search_path='' as $fn$ select private.hub_kpi_report_status_v1(p_tenant_id); $fn$;
revoke all on function public.hub_kpi_report_status_v1(uuid) from public,anon;
grant execute on function public.hub_kpi_report_status_v1(uuid) to authenticated;

create function private.hub_kpi_request_report_sync_v1(p_tenant_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $fn$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI management access required' using errcode='42501';end if;
 insert into private.hub_kpi_report_state(tenant_id,requested_by) values(p_tenant_id,auth.uid())
 on conflict(tenant_id) do update set status='queued',requested_at=clock_timestamp(),requested_by=auth.uid(),error_code=null
 where hub_kpi_report_state.status<>'queued';
 return private.hub_kpi_report_status_v1(p_tenant_id);
end $fn$;
revoke all on function private.hub_kpi_request_report_sync_v1(uuid) from public,anon;
grant execute on function private.hub_kpi_request_report_sync_v1(uuid) to authenticated;
create function public.hub_kpi_request_report_sync_v1(p_tenant_id uuid) returns jsonb
language sql set search_path='' as $fn$ select private.hub_kpi_request_report_sync_v1(p_tenant_id); $fn$;
revoke all on function public.hub_kpi_request_report_sync_v1(uuid) from public,anon;
grant execute on function public.hub_kpi_request_report_sync_v1(uuid) to authenticated;

create function private.hub_kpi_active_report_generation_v1(p_tenant_id uuid) returns uuid
language plpgsql stable security definer set search_path='' as $fn$
declare generation uuid;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then raise exception 'Prepared KPI report unavailable' using errcode='55000';end if;
 return generation;
end $fn$;
revoke all on function private.hub_kpi_active_report_generation_v1(uuid) from public,anon,authenticated;

-- Only the postgres-owned cron job may execute this worker. The locally scoped
-- user context remains subject to existing Hub permissions and is restored.
create function private.hub_kpi_run_report_jobs_v1() returns void
language plpgsql set search_path='' as $fn$
declare job record; generation uuid; first_year integer; last_year integer; yr integer;
 claims text:=current_setting('request.jwt.claims',true); subject text:=current_setting('request.jwt.claim.sub',true);
 local_now timestamp:=clock_timestamp() at time zone 'Europe/Stockholm';
begin
 if not pg_try_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0)) then return;end if;
 if local_now::time>=time '03:00' then
 update private.hub_kpi_report_state set status='queued',requested_at=clock_timestamp(),last_nightly_date=local_now::date,error_code=null
 where (last_nightly_date is null or last_nightly_date<local_now::date) and status<>'queued';
 end if;
 for job in select * from private.hub_kpi_report_state where status='queued' order by requested_at for update skip locked loop
 begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',job.requested_by,'role','authenticated')::text,true);
 perform set_config('request.jwt.claim.sub',job.requested_by::text,true);
 if not public.hub_has_permission(job.tenant_id,'kpi.manage') then raise exception 'Report job permission revoked' using errcode='42501';end if;
 last_year:=extract(year from local_now)::integer-case when extract(month from local_now)<9 then 1 else 0 end+1;
 select least(last_year-5,coalesce(min(extract(year from occurred_on)::integer-case when extract(month from occurred_on)<9 then 1 else 0 end),last_year-5)) into first_year
 from public.kpi_import_rows where tenant_id=job.tenant_id and is_valid and data_kind in ('revenue','cost') and occurred_on is not null;
 if first_year<2000 then raise exception 'Invalid historical fiscal year';end if;
 insert into private.hub_kpi_report_generations(tenant_id,first_fiscal_year,last_fiscal_year) values(job.tenant_id,first_year,last_year) returning id into generation;
 insert into private.hub_kpi_prepared_hub_objects select generation,t.* from public.hub_objects t where tenant_id=job.tenant_id and object_type='Vehicle';
insert into private.hub_kpi_prepared_hub_transpa_entities select generation,t.* from public.hub_transpa_entities t where tenant_id=job.tenant_id and entity_type='vehicle';
insert into private.hub_kpi_prepared_hub_vehicle_meter_readings select generation,t.* from public.hub_vehicle_meter_readings t where tenant_id=job.tenant_id and reading_type='odometer_km';
insert into private.hub_kpi_prepared_kpi_business_groups select generation,t.* from public.kpi_business_groups t where tenant_id=job.tenant_id;
insert into private.hub_kpi_prepared_kpi_import_rows select generation,t.* from public.kpi_import_rows t where tenant_id=job.tenant_id and data_kind='next_historical_time';
insert into private.hub_kpi_prepared_kpi_project_classification_periods select generation,t.* from public.kpi_project_classification_periods t where tenant_id=job.tenant_id;
insert into private.hub_kpi_prepared_kpi_settings select generation,t.* from public.kpi_settings t where tenant_id=job.tenant_id;
insert into private.hub_kpi_prepared_kpi_transpa_time_facts select generation,t.* from public.kpi_transpa_time_facts t where tenant_id=job.tenant_id;
insert into private.hub_kpi_prepared_kpi_unit_periods select generation,t.* from public.kpi_unit_periods t where tenant_id=job.tenant_id;
insert into private.hub_kpi_prepared_kpi_units select generation,t.* from public.kpi_units t where tenant_id=job.tenant_id;
insert into private.hub_kpi_prepared_kpi_vehicle_distance_periods select generation,t.* from public.kpi_vehicle_distance_periods t where tenant_id=job.tenant_id;
 insert into private.hub_kpi_prepared_daily
 select generation,d.* from public.kpi_transpa_vehicle_time_daily_secure(job.tenant_id,'2000-01-01',make_date(last_year+1,8,31)) d;
 for yr in first_year..last_year loop
 insert into private.hub_kpi_prepared_facts select generation,job.tenant_id,yr,f.*
 from private.hub_kpi_filtered_classified_facts_v1(job.tenant_id,make_date(yr,9,1),make_date(yr+1,8,31),'{}') f;
 end loop;
 if exists(select 1 from private.hub_kpi_prepared_facts where generation_id=generation and (amount is null or amount='NaN'::numeric or occurred_on is null)) then
 raise exception 'Invalid prepared financial facts';end if;
 update private.hub_kpi_report_generations set completed_at=clock_timestamp() where id=generation;
 update private.hub_kpi_report_state set active_generation=generation,synced_at=clock_timestamp(),status='ready',error_code=null,
 last_nightly_date=case when local_now::time>=time '03:00' then local_now::date else last_nightly_date end where tenant_id=job.tenant_id;
 -- Retain the latest two derived generations, never remove raw Hub data.
 delete from private.hub_kpi_report_generations where tenant_id=job.tenant_id and id not in
 (select id from private.hub_kpi_report_generations where tenant_id=job.tenant_id order by completed_at desc nulls last limit 2);
 exception when query_canceled or others then
 update private.hub_kpi_report_state set status='failed',error_code=sqlstate where tenant_id=job.tenant_id;
 raise log 'KPI report preparation failed: tenant %, SQLSTATE %',job.tenant_id,sqlstate;
 end;
 end loop;
 perform set_config('request.jwt.claims',coalesce(claims,''),true);
 perform set_config('request.jwt.claim.sub',coalesce(subject,''),true);
end $fn$;
revoke all on function private.hub_kpi_run_report_jobs_v1() from public,anon,authenticated,service_role;
-- Minute ticks are inexpensive: no rebuild unless explicitly queued or after 03:00.
-- Local clock gate handles Swedish daylight saving without modifying cron.timezone.
select cron.schedule('hub-kpi-prepared-reports-v1','* * * * *',
 'begin isolation level repeatable read; set local statement_timeout=''5min''; select private.hub_kpi_run_report_jobs_v1(); commit;');
