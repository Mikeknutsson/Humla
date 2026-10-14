-- Consolidated canonical allocation engine and read API; validated before rule activation.
-- Canonical, dated allocation. Raw imports are never changed.
create table if not exists private.hub_cost_allocation_applied_v1(
 tenant_id uuid not null,generation_id uuid not null,original_fact_id text not null,
 rule_id uuid not null,status text not null,before_fact jsonb not null,recipients jsonb not null,
 applied_at timestamptz not null default now(),applied_by uuid not null,
 primary key(tenant_id,generation_id,original_fact_id));
alter table private.hub_cost_allocation_applied_v1 enable row level security;
revoke all on private.hub_cost_allocation_applied_v1 from public,anon,authenticated;

alter table private.hub_cost_allocation_applied_v1 add column if not exists rule_snapshot jsonb;
create or replace function private.hub_cost_allocation_plan_v1(p_tenant uuid,p_generation uuid,p_preview boolean default false)
returns table(rule_id uuid,fact_id text,status text,recipients jsonb)
language plpgsql stable security definer set search_path='' set jit='off' as $$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 return query
 with rules as materialized(select r.* from public.hub_cost_allocation_rules r where r.tenant_id=p_tenant and (r.enabled or p_preview) and r.include_in_vehicle_result and r.source_scope is not null),
 periods as materialized(
 select o.id,p.value payload,(p.value->>'valid_from')::date valid_from,(p.value->>'valid_to')::date valid_to,
 p.value->>'name' name,g.name grp,v.id main_id,v.data->>'vehicle_type' vehicle_type,
 p.value#>>'{main_vehicle,source_reference}' registration
 from public.hub_objects o cross join lateral jsonb_array_elements(o.data->'periods')p
 left join public.hub_objects v on v.id::text=p.value#>>'{main_vehicle,object_id}' and v.tenant_id=p_tenant
 left join public.kpi_business_groups g on g.id::text=p.value->>'business_group_id' and g.tenant_id=p_tenant
 where o.tenant_id=p_tenant and o.object_type='EconomicUnit' and (p.value->>'enabled')::boolean),
 source_ids as materialized(
 select r.id rule_id,(private.hub_economic_member_v1(p_tenant,'project',x.ref)->>'object_id')::uuid object_id
 from rules r cross join lateral jsonb_array_elements_text(coalesce(r.source_scope->'project_references',jsonb_build_array(r.source_scope->>'project_reference')))x(ref) where x.ref is not null
 union
 select r.id,(m.value->>'object_id')::uuid from rules r join public.hub_objects o on o.tenant_id=p_tenant and o.object_type='EconomicUnit' and r.source_scope->'source_unit_names' ? (o.data->>'name')
 cross join lateral jsonb_array_elements(o.data->'periods')p cross join lateral jsonb_array_elements(p.value->'members')m where m.value->>'object_id' is not null),
 source_keys as materialized(select distinct s.rule_id,k.identity_type,k.identity_value from source_ids s join public.hub_identity_keys k on k.object_id=s.object_id and k.tenant_id=p_tenant and k.identity_type in('next_project_number','registration_number')),
 source_matches as materialized(
 select distinct f.fact_id,k.rule_id from private.hub_kpi_prepared_display_facts f join source_keys k on k.identity_type='next_project_number' and k.identity_value=f.project where f.tenant_id=p_tenant and f.generation_id=p_generation and f.kind='cost'
 union
 select distinct f.fact_id,k.rule_id from private.hub_kpi_prepared_display_facts f join source_keys k on k.identity_type='registration_number' and k.identity_value=f.vehicle where f.tenant_id=p_tenant and f.generation_id=p_generation and f.kind='cost'
 ),
 matched as materialized(
 select f.*,r.id rule_id,r.allocation_method,r.target_selection_mode,r.selected_object_ids,r.target_scope,r.source_scope,
 count(*)over(partition by f.fact_id) rule_count
 from source_matches sm join private.hub_kpi_prepared_facts f on f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=sm.fact_id join rules r on r.id=sm.rule_id and f.occurred_on>=r.valid_from and (r.valid_to is null or f.occurred_on<=r.valid_to)
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.kind='cost' and not (f.original ? '_humla_cost_rule')

 ), candidates as materialized(
 select f.fact_id,p.id,p.name,p.grp,p.registration
 from matched f join periods p on p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)
 where f.rule_count=1 and f.cost_center=f.source_scope->>'cost_center'
 and not exists(select 1 from source_ids s where s.rule_id=f.rule_id and s.object_id=p.main_id)
 and not (coalesce(f.target_scope->'exclude_unit_names','[]') ? p.name)
 and (
 (f.allocation_method='equal' and ((f.target_selection_mode='selected' and p.id=any(f.selected_object_ids))
 or (f.target_selection_mode='all' and f.target_scope->>'own_trucks_only'='true'
 and (p.vehicle_type='Lastbil' or exists(select 1 from rules confirmed where confirmed.target_scope->>'business_group' in ('Bygg & Anläggning','Kranbilar','Stena') and p.id=any(confirmed.selected_object_ids)))
 and exists(select 1 from public.kpi_project_classification_periods c where c.tenant_id=p_tenant and p.registration=any(c.registrations) and c.cost_center=f.target_scope->>'cost_center' and c.valid_from<=f.occurred_on and (c.valid_to is null or c.valid_to>=f.occurred_on)))))
 or (f.allocation_method='manual' and f.target_scope->>'require_confirmed_vehicle'='true' and exists(
 select 1 from jsonb_array_elements(p.payload->'members')m
 join public.hub_identity_keys k on k.object_id::text=m.value->>'object_id' and k.tenant_id=p_tenant
 where (k.identity_type='registration_number' and k.identity_value=coalesce(nullif(f.vehicle,''),nullif(f.original->>'Registreringsnummer',''),nullif(f.original->>'Regnr','')))
 or (k.identity_type='employee_number' and k.identity_value=coalesce(nullif(f.original->>'employee_id',''),nullif(f.original->>'Anställningsnummer','')))
 or (k.identity_type='next_project_number' and k.identity_value=f.original#>>'{_humla_assignment,project}' and k.identity_value<>f.project))))
 ), recipients as(select c.fact_id,jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'group',c.grp,'vehicle',c.registration) order by c.id) value,count(*) n from (select distinct * from candidates)c group by c.fact_id)
 select f.rule_id,f.fact_id,case when f.rule_count<>1 then 'overlapping_rules' when f.cost_center is distinct from f.source_scope->>'cost_center' then 'cost_center_review'
 when f.original#>>'{_humla_distribution,status}'='allocated' then 'already_distributed_review'
 when f.allocation_method='manual' and coalesce(r.n,0)<>1 then 'identity_review'
 when coalesce(r.n,0)=0 then 'no_eligible_units'
 when f.allocation_method not in('equal','manual') then 'unsupported_method' else 'allocated' end,
 coalesce(r.value,'[]') from matched f left join recipients r on r.fact_id=f.fact_id;
end $$;
revoke all on function private.hub_cost_allocation_plan_v1(uuid,uuid,boolean) from public,anon,authenticated;

create or replace function private.hub_apply_cost_allocation_v1(p_tenant uuid,p_generation uuid)
returns jsonb language plpgsql security definer set search_path='' set jit='off' as $$
declare before_totals jsonb;after_totals jsonb;result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then raise exception 'KPI management required' using errcode='42501';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant)then raise exception 'Generation mismatch';end if;
 perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||p_tenant::text,0));
 create temporary table allocation_plan on commit drop as select p.*,to_jsonb(f) before_fact from private.hub_cost_allocation_plan_v1(p_tenant,p_generation) p join private.hub_kpi_prepared_facts f on f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=p.fact_id;
 if exists(select 1 from pg_temp.allocation_plan where status='overlapping_rules')then raise exception 'Overlapping allocation rules';end if;
 insert into private.hub_cost_allocation_applied_v1(tenant_id,generation_id,original_fact_id,rule_id,status,before_fact,recipients,applied_by,rule_snapshot)
 select p_tenant,p_generation,fact_id,rule_id,status,before_fact,recipients,auth.uid(),(select to_jsonb(r) from public.hub_cost_allocation_rules r where r.id=p.rule_id and r.tenant_id=p_tenant) from pg_temp.allocation_plan p;
 delete from private.hub_kpi_prepared_display_facts d using pg_temp.allocation_plan p where d.tenant_id=p_tenant and d.generation_id=p_generation and d.fact_id=p.fact_id;
 delete from private.hub_kpi_prepared_facts f using pg_temp.allocation_plan p where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=p.fact_id;
 create temporary table allocation_output on commit drop as
 select expanded.*
 from pg_temp.allocation_plan p left join lateral jsonb_array_elements(case when p.status='allocated' then p.recipients else '[]'::jsonb end) with ordinality r(value,ordinality) on true
 cross join lateral(select jsonb_build_object('rule_id',p.rule_id,'status',p.status,'original_fact_id',p.fact_id,'original_amount',(p.before_fact->>'amount')::numeric,'recipient_count',jsonb_array_length(p.recipients),'recipient_unit',r.value->>'id','engine','canonical_cost_rules_v1') evidence)e
 cross join lateral jsonb_populate_record(null::private.hub_kpi_prepared_facts,p.before_fact||jsonb_build_object(
 'fact_id',case when p.status='allocated' then p.fact_id||':rule:'||p.rule_id||':'||(r.value->>'id') else p.fact_id end,
 'amount',case when p.status<>'allocated' then (p.before_fact->>'amount')::numeric when r.ordinality=jsonb_array_length(p.recipients) then (p.before_fact->>'amount')::numeric-round((p.before_fact->>'amount')::numeric/jsonb_array_length(p.recipients),2)*(jsonb_array_length(p.recipients)-1) else round((p.before_fact->>'amount')::numeric/jsonb_array_length(p.recipients),2) end,
 'unit_id',case when p.status='allocated' then r.value->>'id' else p.before_fact->>'unit_id' end,
 'unit_name',case when p.status='allocated' then r.value->>'name' else p.before_fact->>'unit_name' end,
 'vehicle',case when p.status='allocated' then r.value->>'vehicle' else p.before_fact->>'vehicle' end,
 'business_group',case when p.status='allocated' then coalesce(r.value->>'group','Ej klassificerat') else p.before_fact->>'business_group' end,
 'original',(p.before_fact->'original')||jsonb_build_object('_humla_cost_rule',e.evidence,'_humla_distribution',e.evidence),
 'display_original',(p.before_fact->'display_original')||jsonb_build_object('_humla_cost_rule',e.evidence,'_humla_distribution',e.evidence))) expanded;
 insert into private.hub_kpi_prepared_facts select * from pg_temp.allocation_output;
 insert into private.hub_kpi_prepared_display_facts
 select f.generation_id,f.tenant_id,f.fiscal_year,f.fact_id,f.occurred_on,f.kind,f.amount,f.category,f.project,f.vehicle,f.unit_id,f.unit_name,f.business_group,f.source,f.cost_center,f.display_original
 from pg_temp.allocation_output f;
 if exists(select 1 from pg_temp.allocation_plan p left join (select original#>>'{_humla_cost_rule,original_fact_id}' id,sum(amount) amount from pg_temp.allocation_output group by 1)s on s.id=p.fact_id where s.amount is distinct from (p.before_fact->>'amount')::numeric)then raise exception 'Allocation amount mismatch';end if;
 select jsonb_agg(to_jsonb(s) order by s.period_month,s.kind,s.cost_center,s.category) into before_totals from(select date_trunc('month',(before_fact->>'occurred_on')::date) as period_month,before_fact->>'kind' kind,before_fact->>'cost_center' cost_center,before_fact->>'category' category,sum((before_fact->>'amount')::numeric) amount from pg_temp.allocation_plan group by 1,2,3,4)s;
 select jsonb_agg(to_jsonb(s) order by s.period_month,s.kind,s.cost_center,s.category) into after_totals from(select date_trunc('month',occurred_on) as period_month,kind,cost_center,category,sum(amount) amount from pg_temp.allocation_output group by 1,2,3,4)s;
 if before_totals is distinct from after_totals then raise exception 'Allocation changed financial totals';end if;
 select jsonb_build_object('source_rows',count(*),'allocated_rows',count(*)filter(where status='allocated'),'review_rows',count(*)filter(where status<>'allocated'),'allocated_amount',coalesce(sum((before_fact->>'amount')::numeric)filter(where status='allocated'),0)) into result from pg_temp.allocation_plan;
 drop table pg_temp.allocation_plan;
 drop table pg_temp.allocation_output;
 return result;
end $$;
revoke all on function private.hub_apply_cost_allocation_v1(uuid,uuid) from public,anon,authenticated;

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
 perform pg_advisory_xact_lock(hashtextextended('workify-file-import:'||job.tenant_id::text,0));
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
 perform private.hub_material_project_cost_scope_v1(job.tenant_id,generation);
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
 perform private.hub_ps_validate_fuel_v1(job.tenant_id,generation);
perform private.hub_next_validate_revenue_identity_v1(job.tenant_id,generation);
perform private.hub_next_validate_completeness_v1(job.tenant_id,generation);
perform private.hub_next_validate_reexport_generation_v1(job.tenant_id,generation);
perform private.hub_workify_validate_approved_generation_v1(job.tenant_id,generation);
perform private.hub_apply_cost_allocation_v1(job.tenant_id,generation);
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
;
create or replace function public.hub_cost_allocation_status_v1(p_tenant uuid)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read')then raise exception 'KPI access required'using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(s) order by s.rule_id),'[]') into result from(
 select r.id rule_id,count(a.original_fact_id) source_rows,count(a.original_fact_id)filter(where a.status='allocated') allocated_rows,
 count(a.original_fact_id)filter(where a.status<>'allocated') review_rows,
 coalesce(sum((a.before_fact->>'amount')::numeric)filter(where a.status='allocated'),0) allocated_amount,
 coalesce(sum((a.before_fact->>'amount')::numeric)filter(where a.status<>'allocated'),0) review_amount,
 min((a.before_fact->>'occurred_on')::date) period_from,max((a.before_fact->>'occurred_on')::date) period_to
 from public.hub_cost_allocation_rules r left join private.hub_kpi_report_state state on state.tenant_id=r.tenant_id
 left join private.hub_cost_allocation_applied_v1 a on a.tenant_id=r.tenant_id and a.rule_id=r.id and a.generation_id=state.active_generation
 where r.tenant_id=p_tenant group by r.id)s;
 return result;
end $$;
revoke all on function public.hub_cost_allocation_status_v1(uuid) from public,anon;
grant execute on function public.hub_cost_allocation_status_v1(uuid) to authenticated;

