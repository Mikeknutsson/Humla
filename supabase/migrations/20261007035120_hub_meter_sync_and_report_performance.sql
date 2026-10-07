-- Restore indexed nested-loop joins where small canonical lookup tables benefit.
alter function public.hub_kpi_monthly_transport_report_v1(uuid,integer,integer,text,jsonb) set enable_nestloop='on';
alter function private.hub_kpi_prepared_snapshot_v1(uuid,integer,integer[],jsonb) set enable_nestloop='on';
create index if not exists hub_prepared_time_report_lookup on private.hub_kpi_prepared_kpi_transpa_time_facts(generation_id,tenant_id,time_report_id);
create index if not exists hub_prepared_vehicle_id_lookup on private.hub_kpi_prepared_hub_objects(generation_id,tenant_id,(id::text)) where object_type='Vehicle';
create index if not exists hub_prepared_unit_period_lookup on private.hub_kpi_prepared_kpi_unit_periods(generation_id,tenant_id,unit_id,valid_from);
-- Candidate lookup uses text fields to avoid non-immutable timestamp casts in indexes.
create index if not exists hub_meter_canonical_candidate on public.hub_objects(tenant_id,(data->>'reading_type'),(data->>'asset_id'),(data->>'recorded_at'),(data->>'reading_value')) where object_type='VehicleMeterReading';
do $patch$ declare d text; begin
 d:=pg_get_functiondef('public.hub_sync_fordonskontroll_meter_readings(uuid,uuid,text,jsonb)'::regprocedure);
 d:=replace(d,'nullif(o.data->>''asset_id'','''')::uuid=asset_id','o.data->>''asset_id''=asset_id::text');
 -- Keep timestamp/numeric comparisons semantically identical; the first three index keys narrow candidates.
 execute d;
end $patch$;

create table private.hub_fleet_meter_jobs (
 connection_id uuid primary key references public.hub_connections(id),
 tenant_id uuid not null references public.hub_tenants(id),
 run_id uuid not null default gen_random_uuid(),
 status text not null default 'queued' check(status in ('queued','running','partial','completed','failed')),
 since_at timestamptz not null, started_at timestamptz not null default now(),
 successful_through timestamptz, completed_at timestamptz,
 cursors jsonb not null default '{"odometer_readings":{"done":false,"cursor":null},"engine_hour_readings":{"done":false,"cursor":null}}',
 lease_id uuid, lease_until timestamptz, attempts integer not null default 0,
 requested_at timestamptz, last_error text, received integer not null default 0, updated_at timestamptz not null default now()
);
alter table private.hub_fleet_meter_jobs enable row level security;
revoke all on private.hub_fleet_meter_jobs from public,anon,authenticated;

-- Only the authenticated service worker can claim/advance jobs. Tenant comes from the connection.
create function public.hub_fleet_meter_job_v1(p_connection_id uuid,p_action text,p_payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare j private.hub_fleet_meter_jobs; c public.hub_connections; token uuid; watermark timestamptz;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Service worker required' using errcode='42501';end if;
 select * into c from public.hub_connections where id=p_connection_id and connector_type='fordonskontrollen' and status in ('active','error');
 if not found then raise exception 'Connection unavailable';end if;
 perform pg_advisory_xact_lock(hashtextextended('meter:'||p_connection_id::text,0));
 if p_action='claim' then
  select * into j from private.hub_fleet_meter_jobs where connection_id=p_connection_id for update;
  if found and j.lease_until>now() then return jsonb_build_object('skipped','already_running');end if;
  if found and j.status='completed' and (j.completed_at at time zone 'Europe/Stockholm')::date=(now() at time zone 'Europe/Stockholm')::date then return jsonb_build_object('skipped','already_completed_today');end if;
  if not found or j.status='completed' then
   watermark:=coalesce(j.successful_through,(select max(recorded_at) from public.hub_vehicle_meter_readings where connection_id=c.id and tenant_id=c.tenant_id),make_timestamptz(extract(year from now())::int-1,9,1,0,0,0,'Europe/Stockholm'))-interval '1 day';
   insert into private.hub_fleet_meter_jobs(connection_id,tenant_id,since_at) values(c.id,c.tenant_id,watermark)
   on conflict(connection_id) do update set run_id=gen_random_uuid(),status='queued',since_at=watermark,started_at=now(),completed_at=null,cursors=excluded.cursors,attempts=0,received=0,last_error=null;
  end if;
  token:=gen_random_uuid();
  update private.hub_fleet_meter_jobs set status='running',lease_id=token,lease_until=now()+interval '3 minutes',attempts=attempts+1,updated_at=now() where connection_id=c.id returning * into j;
  return to_jsonb(j);
 end if;
 select * into j from private.hub_fleet_meter_jobs where connection_id=c.id and lease_id=(p_payload->>'lease_id')::uuid for update;
 if not found then raise exception 'Stale lease';end if;
 if p_action='progress' then
  if p_payload->>'entity' not in ('odometer_readings','engine_hour_readings') then raise exception 'Invalid entity';end if;
  update private.hub_fleet_meter_jobs set cursors=jsonb_set(cursors,array[p_payload->>'entity'],p_payload->'cursor_state'),received=received+coalesce((p_payload->>'received')::int,0),lease_until=now()+interval '3 minutes',updated_at=now() where connection_id=c.id returning * into j;
 elsif p_action='release' then
  update private.hub_fleet_meter_jobs set status='partial',lease_id=null,lease_until=null,updated_at=now() where connection_id=c.id returning * into j;
 elsif p_action='fail' then
  update private.hub_fleet_meter_jobs set status='failed',lease_id=null,lease_until=null,last_error=left(p_payload->>'error',1000),updated_at=now() where connection_id=c.id returning * into j;
  update public.hub_connections set status='error',last_error='meter_sync: '||j.last_error,last_error_at=now() where id=c.id;
 elsif p_action='complete' then
  if not coalesce((j.cursors#>>'{odometer_readings,done}')::boolean,false) or not coalesce((j.cursors#>>'{engine_hour_readings,done}')::boolean,false) then raise exception 'Incomplete pagination';end if;
  update private.hub_fleet_meter_jobs set status='completed',successful_through=started_at,completed_at=now(),lease_id=null,lease_until=null,last_error=null,updated_at=now() where connection_id=c.id returning * into j;
  update public.hub_connections set status='active',last_success_at=now(),last_error=null,last_error_at=null where id=c.id;
 else raise exception 'Invalid worker action';end if;
 return to_jsonb(j);
end $fn$;
revoke all on function public.hub_fleet_meter_job_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.hub_fleet_meter_job_v1(uuid,text,jsonb) to service_role;

create function private.hub_fleet_meter_tick_v1(p_force boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $fn$
declare c record; worker_key text; requests jsonb:='[]'; request_id bigint;
begin
 select decrypted_secret into worker_key from vault.decrypted_secrets where name='humla_worker_key' limit 1;
 if coalesce(worker_key,'')='' then raise exception 'Worker key unavailable';end if;
 for c in select h.id from public.hub_connections h left join private.hub_fleet_meter_jobs j on j.connection_id=h.id
 where h.connector_type='fordonskontrollen' and h.status in ('active','error')
 and not exists(select 1 from public.hub_connection_sync_settings s where s.connection_id=h.id and not s.enabled)
 and (p_force or extract(hour from now() at time zone 'Europe/Stockholm')=3 or j.status in ('queued','running','partial','failed'))
 and (j.completed_at is null or (j.completed_at at time zone 'Europe/Stockholm')::date<(now() at time zone 'Europe/Stockholm')::date)
 and (j.lease_until is null or j.lease_until<now()) and (j.requested_at is null or j.requested_at<now()-interval '4 minutes')
 and (j.status is distinct from 'failed' or j.attempts<6 or j.updated_at<now()-interval '1 day')
 loop
  select net.http_post(url:='https://vuurtaafxvevbhdzgttq.supabase.co/functions/v1/fordonskontrollen-meter-worker',headers:=jsonb_build_object('Content-Type','application/json','x-humla-worker-key',worker_key),body:=jsonb_build_object('connection_id',c.id),timeout_milliseconds:=120000) into request_id;
  update private.hub_fleet_meter_jobs set requested_at=now() where connection_id=c.id;
  requests:=requests||jsonb_build_array(request_id);
 end loop;
 return jsonb_build_object('request_ids',requests);
end $fn$;
revoke all on function private.hub_fleet_meter_tick_v1(boolean) from public,anon,authenticated;
select cron.schedule('humla-fordonskontrollen-meters','*/5 * * * *','select private.hub_fleet_meter_tick_v1();');
