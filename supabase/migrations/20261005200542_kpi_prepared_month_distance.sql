create table private.hub_kpi_prepared_month_distance(
 generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade,
 tenant_id uuid not null, vehicle_id uuid not null, date_from date not null,date_to date not null,estimate jsonb not null,
 primary key(generation_id,tenant_id,vehicle_id,date_from,date_to));
alter table private.hub_kpi_prepared_month_distance enable row level security;
revoke all on private.hub_kpi_prepared_month_distance from public,anon,authenticated;
create or replace function private.hub_kpi_run_report_jobs_v1() returns void
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
 insert into private.hub_kpi_prepared_month_distance
 select generation,job.tenant_id,v.vehicle_id,m.dt::date,(m.dt+interval '1 month'-interval '1 day')::date,
 private.hub_kpi_interpolated_distance_v1(job.tenant_id,v.vehicle_id,m.dt::date,(m.dt+interval '1 month'-interval '1 day')::date)
 from (select distinct vehicle_id from private.hub_kpi_prepared_hub_vehicle_meter_readings where generation_id=generation) v
 cross join generate_series(make_date(first_year,9,1)::timestamp,make_date(last_year+1,8,1)::timestamp,interval '1 month') m(dt);
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

CREATE OR REPLACE FUNCTION private.hub_kpi_prepared_distance_v1(p_tenant uuid, p_vehicle uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare ts_start timestamptz:=p_from::timestamp at time zone 'Europe/Stockholm'; ts_end timestamptz:=(p_to+1)::timestamp at time zone 'Europe/Stockholm';
 report_generation uuid:=private.hub_kpi_active_report_generation_v1(p_tenant); cached_estimate jsonb;
 a timestamptz;b timestamptz;c timestamptz;d timestamptz; va numeric;vb numeric;vc numeric;vd numeric; vstart numeric;vend numeric;bad boolean;connections integer;
begin
 select estimate into cached_estimate from private.hub_kpi_prepared_month_distance where generation_id=report_generation and tenant_id=p_tenant and vehicle_id=p_vehicle and date_from=p_from and date_to=p_to;
 if cached_estimate is not null then return cached_estimate;end if;
 if p_from is null or p_to<p_from then return jsonb_build_object('basis','missing');end if;
 select max(recorded_at) filter(where recorded_at<=ts_start),min(recorded_at) filter(where recorded_at>=ts_start),
 max(recorded_at) filter(where recorded_at<=ts_end),min(recorded_at) filter(where recorded_at>=ts_end)
 into a,b,c,d from (select id,tenant_id,vehicle_id,connection_id,reading_type,reading_value,recorded_at,external_id,raw_data,created_at,object_id from private.hub_kpi_prepared_hub_vehicle_meter_readings where generation_id=report_generation) where tenant_id=p_tenant and vehicle_id=p_vehicle and reading_type='odometer_km';
 if a is null or b is null or c is null or d is null then return jsonb_build_object('basis','missing_bracketing_readings');end if;
 with points as(select recorded_at,min(reading_value) lo,max(reading_value) hi from (select id,tenant_id,vehicle_id,connection_id,reading_type,reading_value,recorded_at,external_id,raw_data,created_at,object_id from private.hub_kpi_prepared_hub_vehicle_meter_readings where generation_id=report_generation)
 where tenant_id=p_tenant and vehicle_id=p_vehicle and reading_type='odometer_km' and recorded_at between a and d group by recorded_at),
 checked as(select *,lag(hi) over(order by recorded_at) previous from points)
 select max(hi) filter(where recorded_at=a),max(hi) filter(where recorded_at=b),max(hi) filter(where recorded_at=c),max(hi) filter(where recorded_at=d),
 coalesce(bool_or(lo<0 or lo<>hi or lo<previous),true) into va,vb,vc,vd,bad from checked;
 select count(distinct connection_id) into connections from (select id,tenant_id,vehicle_id,connection_id,reading_type,reading_value,recorded_at,external_id,raw_data,created_at,object_id from private.hub_kpi_prepared_hub_vehicle_meter_readings where generation_id=report_generation) where tenant_id=p_tenant and vehicle_id=p_vehicle and reading_type='odometer_km' and recorded_at between a and d;
 if bad or connections<>1 then return jsonb_build_object('basis','invalid_meter_sequence');end if;
 vstart:=case when a=b then va else va+(vb-va)*extract(epoch from(ts_start-a))/extract(epoch from(b-a)) end;
 vend:=case when c=d then vc else vc+(vd-vc)*extract(epoch from(ts_end-c))/extract(epoch from(d-c)) end;
 if vend<vstart then return jsonb_build_object('basis','invalid_meter_sequence');end if;
 return jsonb_build_object('distance_km',vend-vstart,'basis',case when a=b and c=d then 'meter_exact' else 'interpolated' end,
 'start_km',vstart,'end_km',vend,'start_before',a,'start_after',b,'end_before',c,'end_after',d);
end $function$;
