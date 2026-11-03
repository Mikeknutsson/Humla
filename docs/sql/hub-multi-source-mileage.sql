create table if not exists private.hub_kpi_meter_points_v1(
 generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade,
 tenant_id uuid not null,vehicle_id uuid not null,source text not null check(source in('Fordonskontrollen','Piusi','GPS')),
 source_id text not null,recorded_at timestamptz not null,reading_km numeric not null check(reading_km>=0),
 quality text not null,
 primary key(generation_id,source,source_id)
);
create index if not exists hub_kpi_meter_points_asset_date on private.hub_kpi_meter_points_v1(generation_id,tenant_id,vehicle_id,recorded_at);
alter table private.hub_kpi_meter_points_v1 enable row level security;
revoke all on private.hub_kpi_meter_points_v1 from public,anon,authenticated;

create or replace function private.hub_capture_meter_points_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql set search_path='' as $f$
declare cutoff timestamptz;
begin
 select coalesce(completed_at,clock_timestamp()) into cutoff from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant;
 if not found then raise exception 'Unknown report generation';end if;
 insert into private.hub_kpi_meter_points_v1
 select p_generation,p_tenant,m.vehicle_id,'Fordonskontrollen',m.id::text,m.recorded_at,m.reading_value,'source_meter'
 from private.hub_kpi_prepared_hub_vehicle_meter_readings m
 where m.generation_id=p_generation and m.tenant_id=p_tenant and m.reading_type='odometer_km'
 on conflict do nothing;
 insert into private.hub_kpi_meter_points_v1
 select p_generation,p_tenant,f.vehicle_id,'Piusi',f.fuel_transaction_id::text,
 f.transaction_date at time zone 'Europe/Stockholm',f.odometer,'tank_entry'
 from public.hub_fuel_transactions_v f
 join private.hub_kpi_prepared_hub_objects v on v.generation_id=p_generation and v.tenant_id=p_tenant and v.id=f.vehicle_id and v.object_type='Vehicle'
 where f.tenant_id=p_tenant and f.source_system='piusi_bsmart' and f.odometer_unit='K_OT_KM' and f.odometer>0
 and f.transaction_date is not null and f.updated_at<=cutoff and not f.exclude_from_vehicle_kpi
 on conflict do nothing;
 insert into private.hub_kpi_meter_points_v1
 select p_generation,p_tenant,v.id,'GPS',p.id::text,p.observed_at,p.odometer_km,'imported_meter_confirmed_identity'
 from public.hub_vehicle_position_observations p
 left join lateral(select count(distinct k.object_id)n,(array_agg(distinct k.object_id))[1]id
 from public.hub_identity_keys k where k.tenant_id=p_tenant and k.identity_type='registration_number' and k.confidence=1
 and public.hub_normalize_vehicle_registration(k.identity_value)=public.hub_normalize_vehicle_registration(p.vehicle_registration))matched on p.vehicle_object_id is null
 join private.hub_kpi_prepared_hub_objects v on v.generation_id=p_generation and v.tenant_id=p_tenant and v.id=coalesce(p.vehicle_object_id,case when matched.n=1 then matched.id end) and v.object_type='Vehicle'
 where p.tenant_id=p_tenant and p.odometer_km>=0 and p.created_at<=cutoff and p.source_system='gps_xml_import' and nullif(p.source_record_id,'')is not null
 on conflict do nothing;
end $f$;
revoke all on function private.hub_capture_meter_points_v1(uuid,uuid) from public,anon,authenticated;

create or replace function private.hub_meter_series_v1(p_tenant uuid,p_generation uuid,p_vehicle uuid,p_from date,p_to date)
returns jsonb language sql stable set search_path='' as $f$
with all_points as materialized(select source,source_id,recorded_at at,reading_km km,quality from private.hub_kpi_meter_points_v1 where tenant_id=p_tenant and generation_id=p_generation and vehicle_id=p_vehicle),
 limits as(select coalesce(max(at)filter(where at<=p_from::timestamp at time zone 'Europe/Stockholm'),min(at)) lo,
 coalesce(min(at)filter(where at>=(p_to+1)::timestamp at time zone 'Europe/Stockholm'),max(at)) hi from all_points),
 window_points as materialized(select p.*from all_points p cross join limits l where p.at between l.lo and l.hi),
 times as(select at,min(km)lo,max(km)hi from window_points group by at),
 checked as(select *,lag(hi)over(order by at) previous from times),
 conflicts as(select count(*)filter(where lo<>hi or lo<previous) n from checked),
 chosen as materialized(select p.*from window_points p cross join conflicts c where c.n=0 or p.source='Fordonskontrollen')
select jsonb_build_object('points',coalesce((select jsonb_agg(to_jsonb(p)order by at,source,source_id)from chosen p),'[]'),
 'sources',coalesce((select jsonb_agg(source order by source)from(select distinct source from chosen)s),'[]'),
 'conflicts',c.n,'selection',case when c.n>0 then 'fordonskontrollen_after_conflict' else 'consistent_meter_series'end,
 'note',case when c.n>0 then 'Motstridiga mätarställningar. Kompletterande källor har inte använts i denna period.'end)
from conflicts c;
$f$;
revoke all on function private.hub_meter_series_v1(uuid,uuid,uuid,date,date) from public,anon,authenticated;

create or replace function private.hub_meter_span_engine_v1(p_series jsonb,p_from date,p_to date)
returns jsonb language plpgsql immutable set search_path='' as $f$
declare ts timestamptz:=p_from::timestamp at time zone 'Europe/Stockholm';te timestamptz:=(p_to+1)::timestamp at time zone 'Europe/Stockholm';
 a timestamptz;b timestamptz;c timestamptz;d timestamptz;va numeric;vb numeric;vc numeric;vd numeric;bad boolean;start_km numeric;end_km numeric;
 meta jsonb:=jsonb_build_object('sources',coalesce(p_series->'sources','[]'::jsonb),'conflicts',coalesce(p_series->'conflicts','0'::jsonb),'selection',p_series->'selection','note',p_series->'note');
begin
 if p_from is null or p_to is null or p_to<p_from then return meta||jsonb_build_object('basis','invalid_period');end if;
 select max(at)filter(where at<=ts),min(at)filter(where at>=ts),max(at)filter(where at<=te),min(at)filter(where at>=te)
 into a,b,c,d from jsonb_to_recordset(p_series->'points')x(at timestamptz,km numeric);
 if a is null or b is null or c is null or d is null then return meta||jsonb_build_object('basis','missing_bracketing_readings');end if;
 with points as(select at,min(km)lo,max(km)hi from jsonb_to_recordset(p_series->'points')x(at timestamptz,km numeric)where at between a and d group by at),
 checked as(select *,lag(hi)over(order by at) previous from points)
 select max(hi)filter(where at=a),max(hi)filter(where at=b),max(hi)filter(where at=c),max(hi)filter(where at=d),coalesce(bool_or(lo<0 or lo<>hi or lo<previous),true)
 into va,vb,vc,vd,bad from checked;
 if bad then return meta||jsonb_build_object('basis','invalid_meter_sequence');end if;
 start_km:=case when a=b then va else va+(vb-va)*extract(epoch from(ts-a))/extract(epoch from(b-a))end;
 end_km:=case when c=d then vc else vc+(vd-vc)*extract(epoch from(te-c))/extract(epoch from(d-c))end;
 if end_km<start_km then return meta||jsonb_build_object('basis','invalid_meter_sequence');end if;
 return meta||jsonb_build_object('distance_km',end_km-start_km,'basis',case when a=b and c=d then 'meter_exact'else'interpolated'end,
 'start_km',start_km,'end_km',end_km,'start_before',a,'start_after',b,'end_before',c,'end_after',d);
end $f$;
revoke all on function private.hub_meter_span_engine_v1(jsonb,date,date) from public,anon,authenticated;

create or replace function private.hub_foreman_meter_span_v1(p_tenant uuid,p_generation uuid,p_vehicle uuid,p_from date,p_to date)
returns jsonb language sql stable set search_path='' set jit='off' as $f$
 select private.hub_meter_span_engine_v1(private.hub_meter_series_v1(p_tenant,p_generation,p_vehicle,p_from,p_to),p_from,p_to);
$f$;
revoke all on function private.hub_foreman_meter_span_v1(uuid,uuid,uuid,date,date)from public,anon,authenticated;
create or replace function private.hub_kpi_prepared_distance_v1(p_tenant uuid,p_vehicle uuid,p_from date,p_to date)
returns jsonb language plpgsql stable set search_path='' set jit='off' as $f$
declare g uuid:=private.hub_kpi_active_report_generation_v1(p_tenant);
begin return private.hub_foreman_meter_span_v1(p_tenant,g,p_vehicle,p_from,p_to);end $f$;
revoke all on function private.hub_kpi_prepared_distance_v1(uuid,uuid,date,date)from public,anon,authenticated;
alter function private.hub_meter_series_v1(uuid,uuid,uuid,date,date)set jit='off';

CREATE OR REPLACE FUNCTION private.hub_foreman_mileage_v1(p_tenant uuid, p_report jsonb, p_user uuid, p_months integer[], p_group text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare g uuid:=(p_report->>'generation')::uuid; df date:=(p_report->>'from')::date; dt date:=(p_report->>'to')::date;
 result jsonb; centers text[]; all_transport boolean;
begin
 if auth.uid() is null then raise exception 'Access denied' using errcode='42501';end if;
 select p.cost_centers into centers from private.hub_foreman_access_plans p
 where p.tenant_id=p_tenant and p.auth_user_id=coalesce(p_user,auth.uid()) and p.status='active';
 select p_user is null and exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role='owner') into all_transport;
 with report_units as materialized(select u,(u->>'unit_id')::uuid id from jsonb_array_elements(p_report->'units')u where u->>'unit_id' is not null),
 days as materialized(select d::date d from generate_series(df,dt,interval '1 day')d where p_months is null or extract(month from d)::int=any(p_months)),
 versions as materialized(
 select u.id,v.valid_from,v.valid_to,coalesce((v.payload->>'enabled')::boolean,u.enabled) enabled,
 nullif(trim(v.payload->>'main_vehicle'),'') registration,v.payload->>'business_group_id' group_id
 from private.hub_kpi_prepared_kpi_units u join private.hub_kpi_prepared_kpi_unit_periods v on v.tenant_id=u.tenant_id and v.generation_id=u.generation_id and v.unit_id=u.id
 where u.tenant_id=p_tenant and u.generation_id=g and u.id in(select id from report_units)
 union all
 select u.id,u.valid_from,u.valid_to,u.enabled,case when u.unit_type='vehicle' and cardinality(u.registrations)=1 then u.registrations[1] end,null
 from private.hub_kpi_prepared_kpi_units u where u.tenant_id=p_tenant and u.generation_id=g and u.id in(select id from report_units)
 and not exists(select 1 from private.hub_kpi_prepared_kpi_unit_periods v where v.tenant_id=p_tenant and v.generation_id=g and v.unit_id=u.id)
 ),
 configured as materialized(select r.id,d.d,min(v.registration) registration,min(v.group_id) group_id
 from report_units r cross join days d join versions v on v.id=r.id and v.valid_from<=d.d and(v.valid_to is null or v.valid_to>=d.d)
 group by r.id,d.d having count(*)=1 and bool_and(v.enabled) and min(v.registration)is not null),
 assets as materialized(select public.hub_normalize_vehicle_registration(o.data->>'registration_number') registration,(array_agg(o.id))[1] asset_id
 from private.hub_kpi_prepared_hub_objects o where o.tenant_id=p_tenant and o.generation_id=g and o.object_type='Vehicle' group by 1 having count(*)=1),
 source_series as materialized(select a.asset_id vehicle_id,private.hub_meter_series_v1(p_tenant,g,a.asset_id,df,dt) value
 from assets a where exists(select 1 from configured c where c.registration=a.registration)),
 bounds as materialized(select s.vehicle_id,min(p.at)lo,max(p.at)hi from source_series s cross join lateral jsonb_to_recordset(s.value->'points')p(at timestamptz)group by s.vehicle_id),
 scoped_days as materialized(select c.*,a.asset_id
 from configured c join assets a on a.registration=c.registration
 where (case when all_transport or centers is not null then exists(
 select 1 from private.hub_kpi_prepared_kpi_project_classification_periods p where p.tenant_id=p_tenant and p.generation_id=g and c.registration=any(p.registrations)
 and p.valid_from<=c.d and(p.valid_to is null or p.valid_to>=c.d)
 group by c.registration having count(distinct p.cost_center)=1 and bool_and(case when all_transport then p.cost_center='30' else p.cost_center=any(centers) end))
 else exists(select 1 from public.hub_transport_leader_units a where a.tenant_id=p_tenant and a.user_id=coalesce(p_user,auth.uid()) and a.unit_id=c.id and a.valid_from<=c.d and(a.valid_to is null or a.valid_to>=c.d))end)
 and (p_group is null or exists(select 1 from private.hub_kpi_prepared_kpi_business_groups b where b.tenant_id=p_tenant and b.generation_id=g and b.id::text=c.group_id and b.name=p_group))),
 covered_days as materialized(select s.*,s.d-row_number()over(partition by s.id,s.asset_id order by s.d)::int island
 from scoped_days s join bounds b on b.vehicle_id=s.asset_id where b.lo<=s.d::timestamp at time zone 'Europe/Stockholm' and b.hi>=(s.d+1)::timestamp at time zone 'Europe/Stockholm'),
 spans as materialized(select id,asset_id,min(registration) registration,min(d) date_from,max(d) date_to,count(*) n
 from covered_days group by id,asset_id,island),
 estimates as materialized(select s.*,private.hub_foreman_meter_span_v1(p_tenant,g,s.asset_id,s.date_from,s.date_to) evidence from spans s),
 good as materialized(select * from estimates where (evidence->>'distance_km')::numeric>=0),
 financial as materialized(select f.unit_id,f.occurred_on,f.kind,f.category,f.amount
 from private.hub_transport_leader_facts_v2(p_tenant,df,dt,p_user) f
 where (p_months is null or extract(month from f.occurred_on)::int=any(p_months)) and(p_group is null or coalesce(nullif(f.business_group,''),'Ej klassificerat')=p_group)),
 amounts as(select s.id,sum(f.amount)filter(where f.kind='cost') cost,sum(f.amount)filter(where f.kind='cost'and f.category='fuel') fuel
 from good s left join financial f on f.unit_id=s.id and f.occurred_on between s.date_from and s.date_to group by s.id),
 distance as(select id,sum((evidence->>'distance_km')::numeric)/10 mil,sum(n) covered_days,min(date_from) date_from,max(date_to) date_to,
 bool_or(evidence->>'basis'='interpolated') estimated,
 jsonb_agg(jsonb_build_object('from',date_from,'to',date_to,'vehicle',registration,'mil',round((evidence->>'distance_km')::numeric/10,2),'basis',evidence->>'basis','sources',evidence->'sources')order by date_from) segments from good group by id),
 published as(select r.id,jsonb_build_object(
 'source',coalesce((select string_agg(distinct src, ' + ' order by src)from jsonb_array_elements(d.segments)s cross join lateral jsonb_array_elements_text(s->'sources')src),'Humla Hub'),
 'source_conflicts',(select coalesce(max((s.value->>'conflicts')::int),0)from source_series s where exists(select 1 from scoped_days sd where sd.id=r.id and sd.asset_id=s.vehicle_id)),
 'source_note',(select max(s.value->>'note')from source_series s where exists(select 1 from scoped_days sd where sd.id=r.id and sd.asset_id=s.vehicle_id)),
 'generation',g,'distance_mil',round(d.mil,2),
 'cost_per_mil',round(a.cost/nullif(d.mil,0),2),'fuel_cost_per_mil',round(a.fuel/nullif(d.mil,0),2),
 'matched_cost',round(a.cost,2),'matched_fuel_cost',round(a.fuel,2),
 'from',d.date_from,'to',d.date_to,'covered_days',coalesce(d.covered_days,0),'selected_days',(select count(*)from days),
 'complete',coalesce(d.covered_days=(select count(*)from days),false),'estimated',coalesce(d.estimated,false),
 'status',case when d.mil=0 then 'zero_distance' when d.mil is null then 'missing' when d.covered_days<(select count(*)from days)then 'partial' else 'complete'end,
 'segments',coalesce(d.segments,'[]'::jsonb),
 'reason',case when d.mil is null then 'Mätningar eller säker huvudbilskoppling saknas för perioden.' when d.mil=0 then 'Ingen körsträcka i mätunderlaget; kr/mil kan inte beräknas.'end) mileage
 from report_units r left join distance d on d.id=r.id left join amounts a on a.id=r.id)
 select jsonb_set(p_report,'{units}',coalesce((select jsonb_agg(case when p.id is not null then u||jsonb_build_object('mileage',p.mileage)else u end order by ord)
 from jsonb_array_elements(p_report->'units')with ordinality r(u,ord) left join published p on p.id=(u->>'unit_id')::uuid),'[]'))into result;
 return result;
end $function$

;
CREATE OR REPLACE FUNCTION private.hub_fleet_meter_usage_v1(p_tenant uuid, p_asset uuid, p_type text, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare a timestamptz;b timestamptz;c timestamptz;d timestamptz;va numeric;vb numeric;vc numeric;vd numeric;bad boolean;n integer;
 series_result jsonb;generation uuid;
 ts timestamptz:=p_from::timestamp at time zone 'Europe/Stockholm';te timestamptz:=(p_to+1)::timestamp at time zone 'Europe/Stockholm';
begin
 if p_type='odometer_km' then
  select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant;
  series_result:=private.hub_foreman_meter_span_v1(p_tenant,generation,p_asset,p_from,p_to);
  return series_result||jsonb_build_object('value',series_result->'distance_km');
 end if;
 select max(recorded_at) filter(where recorded_at<=ts),min(recorded_at) filter(where recorded_at>=ts),max(recorded_at) filter(where recorded_at<=te),min(recorded_at) filter(where recorded_at>=te)
 into a,b,c,d from public.hub_vehicle_meter_readings where tenant_id=p_tenant and vehicle_id=p_asset and reading_type=p_type;
 if a is null or b is null or c is null or d is null then return jsonb_build_object('basis','missing_bracketing_readings');end if;
 with points as(select recorded_at,min(reading_value) lo,max(reading_value) hi from public.hub_vehicle_meter_readings
 where tenant_id=p_tenant and vehicle_id=p_asset and reading_type=p_type and recorded_at between a and d group by 1),
 checked as(select *,lag(hi) over(order by recorded_at) previous from points)
 select max(hi) filter(where recorded_at=a),max(hi) filter(where recorded_at=b),max(hi) filter(where recorded_at=c),max(hi) filter(where recorded_at=d),coalesce(bool_or(lo<0 or lo<>hi or lo<previous),true)
 into va,vb,vc,vd,bad from checked;
 select count(distinct connection_id) into n from public.hub_vehicle_meter_readings where tenant_id=p_tenant and vehicle_id=p_asset and reading_type=p_type and recorded_at between a and d;
 if bad or n<>1 then return jsonb_build_object('basis','invalid_meter_sequence');end if;
 return jsonb_build_object('value',(case when c=d then vc else vc+(vd-vc)*extract(epoch from(te-c))/extract(epoch from(d-c)) end)-(case when a=b then va else va+(vb-va)*extract(epoch from(ts-a))/extract(epoch from(b-a)) end),
 'basis',case when a=b and c=d then 'meter_exact' else 'interpolated' end,'start_before',a,'start_after',b,'end_before',c,'end_after',d);
end $function$

;
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
 perform private.hub_capture_meter_points_v1(job.tenant_id,generation);
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
 private.hub_foreman_meter_span_v1(job.tenant_id,generation,v.vehicle_id,m.dt::date,(m.dt+interval '1 month'-interval '1 day')::date)
 from (select distinct vehicle_id from private.hub_kpi_meter_points_v1 where generation_id=generation) v
 cross join generate_series(make_date(first_year,9,1)::timestamp,make_date(last_year+1,8,1)::timestamp,interval '1 month') m(dt);
 if exists(select 1 from private.hub_kpi_prepared_facts where generation_id=generation and (amount is null or amount='NaN'::numeric or occurred_on is null)) then
 raise exception 'Invalid prepared financial facts';end if;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
phase:='hub_kpi_publish_provisional_supplier_costs_v1';phase_started:=clock_timestamp();
perform private.hub_kpi_publish_provisional_supplier_costs_v1(job.tenant_id,generation);
metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
phase:='hub_ps_validate_fuel_v1';phase_started:=clock_timestamp();
perform private.hub_ps_validate_fuel_v1(job.tenant_id,generation);
metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
phase:='hub_next_validate_revenue_identity_v1';phase_started:=clock_timestamp();
perform private.hub_next_validate_revenue_identity_v1(job.tenant_id,generation);
metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
phase:='hub_next_validate_completeness_v1';phase_started:=clock_timestamp();
perform private.hub_next_validate_completeness_v1(job.tenant_id,generation);
metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
phase:='hub_next_validate_reexport_generation_v1';phase_started:=clock_timestamp();
perform private.hub_next_validate_reexport_generation_v1(job.tenant_id,generation);
metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
phase:='hub_workify_validate_approved_generation_v1';phase_started:=clock_timestamp();
perform private.hub_workify_validate_approved_generation_v1(job.tenant_id,generation);
metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
phase:='hub_apply_workify_article_units_v1';phase_started:=clock_timestamp();
perform private.hub_apply_workify_article_units_v1(job.tenant_id,generation);
metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
perform private.hub_apply_stena_priority_v1(job.tenant_id,generation);
phase:='hub_publish_approved_time_costs_v1';phase_started:=clock_timestamp();
perform private.hub_publish_approved_time_costs_v1(job.tenant_id,generation);
metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
phase:='hub_apply_cost_allocation_v1';phase_started:=clock_timestamp();
perform private.hub_apply_cost_allocation_v1(job.tenant_id,generation); metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
phase:='hub_prepare_billable_hours_v1';phase_started:=clock_timestamp();
perform private.hub_prepare_billable_hours_v1(job.tenant_id,generation);
metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
phase:='hub_resolve_remaining_units_v1';phase_started:=clock_timestamp();
analyze private.hub_kpi_prepared_facts;analyze private.hub_kpi_prepared_display_facts;
perform private.hub_resolve_remaining_units_v1(job.tenant_id,generation);

 -- hub_multisignal_worker_v2: bounded publication, never a financial filter.
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='probability_mapping';phase_started:=clock_timestamp();
 metrics:=metrics||jsonb_build_object('probability_result',private.hub_apply_probability_mapping_v2(job.tenant_id,generation,make_date(extract(year from local_now)::int-1,9,1),local_now::date,100,true));
 perform private.hub_apply_saw_activity_v1(job.tenant_id,generation);
 perform private.hub_neutralize_internal_material_profit_v1(job.tenant_id,generation);
 perform private.hub_saw_material_value_v1(job.tenant_id,generation);
perform private.hub_allocate_saw_supplier_common_v1(job.tenant_id,generation);
perform private.hub_apply_monthly_overhead_v1(job.tenant_id,generation);
perform private.hub_apply_yard_saw_share_v1(job.tenant_id,generation);
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