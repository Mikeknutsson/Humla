-- Preserve atomic generation publication and all financial rules.
-- Only worker query planning/memory and private diagnostics change.
alter table private.hub_kpi_report_state
 add column if not exists last_job_metrics jsonb,
 add column if not exists last_error_details jsonb;
CREATE OR REPLACE FUNCTION private.hub_kpi_run_report_jobs_v1()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
 SET plan_cache_mode TO 'force_custom_plan'
 SET work_mem TO '32MB'
AS $function$
declare job record; generation uuid; first_year integer; last_year integer; yr integer;
 claims text:=current_setting('request.jwt.claims',true); subject text:=current_setting('request.jwt.claim.sub',true);
 phase text; phase_started timestamptz; metrics jsonb; failure_context text; failure_message text;
 local_now timestamp:=clock_timestamp() at time zone 'Europe/Stockholm';
begin
 if not pg_try_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0)) then return;end if;
 if local_now::time>=time '03:20' then
 update private.hub_kpi_report_state set status='queued',requested_at=clock_timestamp(),last_nightly_date=local_now::date,error_code=null
 where (last_nightly_date is null or last_nightly_date<local_now::date) and status<>'queued';
 end if;
 for job in select * from private.hub_kpi_report_state where status='queued' order by requested_at for update skip locked loop
 begin
 phase:='snapshot'; phase_started:=clock_timestamp(); metrics:='{}'::jsonb;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',job.requested_by,'role','authenticated')::text,true);
 perform set_config('request.jwt.claim.sub',job.requested_by::text,true);
 if not public.hub_has_permission(job.tenant_id,'kpi.manage') then raise exception 'Report job permission revoked' using errcode='42501';end if;
 last_year:=extract(year from local_now)::integer-case when extract(month from local_now)<9 then 1 else 0 end+1;
 select least(last_year-5,coalesce(min(extract(year from occurred_on)::integer-case when extract(month from occurred_on)<9 then 1 else 0 end),last_year-5)) into first_year
 from public.kpi_import_rows where tenant_id=job.tenant_id and is_valid and data_kind in ('revenue','cost') and occurred_on is not null;
 if first_year<2000 then raise exception 'Invalid historical fiscal year';end if;
 insert into private.hub_kpi_report_generations(tenant_id,first_fiscal_year,last_fiscal_year) values(job.tenant_id,first_year,last_year) returning id into generation;
 insert into private.hub_kpi_prepared_hub_objects select generation,t.* from public.hub_objects t where tenant_id=job.tenant_id and object_type in ('Vehicle','FuelTransaction');
 insert into private.hub_kpi_prepared_fuel_reviews select generation,t.* from public.kpi_bsmart_cost_reviews t where t.tenant_id=job.tenant_id;
 insert into private.hub_kpi_prepared_fuel_state(generation_id,last_connector_success,connector_status) select generation,max(last_success_at),max(status) from public.hub_connections where tenant_id=job.tenant_id and connector_type='piusi_bsmart';
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
 analyze private.hub_kpi_prepared_hub_objects;
 analyze private.hub_kpi_prepared_kpi_unit_periods;
 analyze private.hub_kpi_prepared_kpi_project_classification_periods;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='daily_time'; phase_started:=clock_timestamp();
 insert into private.hub_kpi_prepared_daily
 select generation,d.* from public.kpi_transpa_vehicle_time_daily_secure(job.tenant_id,'2000-01-01',make_date(last_year+1,8,31)) d;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='financial_facts'; phase_started:=clock_timestamp();
 for yr in first_year..last_year loop
 insert into private.hub_kpi_prepared_facts select generation,job.tenant_id,yr,f.*,jsonb_build_object('time_report_id',f.original->'time_report_id','_humla_distribution',jsonb_build_object('status',f.original#>'{_humla_distribution,status}'))
 from private.hub_kpi_filtered_classified_facts_v1(job.tenant_id,make_date(yr,9,1),make_date(yr+1,8,31),'{}') f;
 end loop;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 -- The new generation is invisible to autovacuum until commit. Refresh the
 -- planner's estimates here, before updates and joins on those new rows.
 analyze private.hub_kpi_prepared_facts;
 phase:='material'; phase_started:=clock_timestamp();
 perform private.hub_kpi_separate_material_v1(job.tenant_id,generation);
 update private.hub_kpi_prepared_facts set display_original=display_original||jsonb_build_object('_humla_material_separation',original->'_humla_material_separation') where generation_id=generation and original?'_humla_material_separation';

 update private.hub_kpi_prepared_facts set display_original=display_original||jsonb_build_object('_humla_invoice',jsonb_build_object(
 'order_number',nullif(trim(original->>'Ordernummer'),''),
 'article_date',private.hub_kpi_workify_date_v1(original->>'Artikeldatum'),
 'invoice_date',private.hub_kpi_workify_date_v1(coalesce(nullif(trim(original->>'Fakturadatum'),''),nullif(trim(original->>'Fakturerad'),''))),
 'invoice_text',coalesce(nullif(trim(original->>'Fakturadatum'),''),nullif(trim(original->>'Fakturerad'),'')),
 'customer_name',original->>'Kundnamn',
 'end_text',coalesce(nullif(trim(original->>'Slutdatum'),''),nullif(trim(original->>'PlaneradKlart'),'')),
 'end_date',private.hub_kpi_workify_date_v1(coalesce(nullif(trim(original->>'Slutdatum'),''),nullif(trim(original->>'PlaneradKlart'),'')))))
 where generation_id=generation and source='Workify' and kind='revenue';
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='fuel'; phase_started:=clock_timestamp();
 perform private.hub_kpi_prepare_piusi_facts_v1(job.tenant_id,generation);
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='display'; phase_started:=clock_timestamp();
 insert into private.hub_kpi_prepared_display_facts select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original as original from private.hub_kpi_prepared_facts where generation_id=generation;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='distance'; phase_started:=clock_timestamp();
 insert into private.hub_kpi_prepared_month_distance
 select generation,job.tenant_id,v.vehicle_id,m.dt::date,(m.dt+interval '1 month'-interval '1 day')::date,
 private.hub_kpi_interpolated_distance_v1(job.tenant_id,v.vehicle_id,m.dt::date,(m.dt+interval '1 month'-interval '1 day')::date)
 from (select distinct vehicle_id from private.hub_kpi_prepared_hub_vehicle_meter_readings where generation_id=generation) v
 cross join generate_series(make_date(first_year,9,1)::timestamp,make_date(last_year+1,8,1)::timestamp,interval '1 month') m(dt);
 if exists(select 1 from private.hub_kpi_prepared_facts where generation_id=generation and (amount is null or amount='NaN'::numeric or occurred_on is null)) then
 raise exception 'Invalid prepared financial facts';end if;
 update private.hub_kpi_report_generations set completed_at=clock_timestamp() where id=generation;
 update private.hub_kpi_report_state set active_generation=generation,synced_at=clock_timestamp(),status='ready',error_code=null,
 last_nightly_date=case when local_now::time>=time '03:20' then local_now::date else last_nightly_date end where tenant_id=job.tenant_id;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='cleanup'; phase_started:=clock_timestamp();
 -- Retain the latest two derived generations, never remove raw Hub data.
 delete from private.hub_kpi_report_generations where tenant_id=job.tenant_id and id not in
 (select id from private.hub_kpi_report_generations where tenant_id=job.tenant_id order by completed_at desc nulls last limit 2);
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 update private.hub_kpi_report_state set last_job_metrics=metrics,last_error_details=null where tenant_id=job.tenant_id;
 exception when query_canceled or others then
 get stacked diagnostics failure_context=PG_EXCEPTION_CONTEXT,failure_message=MESSAGE_TEXT;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 update private.hub_kpi_report_state set status='failed',error_code=sqlstate,last_job_metrics=metrics,last_error_details=jsonb_build_object('phase',phase,'message',failure_message,'context',failure_context) where tenant_id=job.tenant_id;
 raise log 'KPI report preparation failed: tenant %, SQLSTATE %',job.tenant_id,sqlstate;
 end;
 end loop;
 perform set_config('request.jwt.claims',coalesce(claims,''),true);
 perform set_config('request.jwt.claim.sub',coalesce(subject,''),true);
end $function$

