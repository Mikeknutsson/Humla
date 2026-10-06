-- Monthly-report-only prepared fuel evidence; retain the existing daily worker schedule.
create table private.hub_kpi_prepared_fuel_reviews (generation_id uuid not null references private.hub_kpi_report_generations(id) on delete cascade, like public.kpi_bsmart_cost_reviews including defaults);
create index on private.hub_kpi_prepared_fuel_reviews(generation_id,tenant_id,hub_object_id);
alter table private.hub_kpi_prepared_fuel_reviews enable row level security;
revoke all on private.hub_kpi_prepared_fuel_reviews from public,anon,authenticated;
create table private.hub_kpi_prepared_fuel_state(generation_id uuid primary key references private.hub_kpi_report_generations(id) on delete cascade,captured_at timestamptz not null default now(),last_connector_success timestamptz,connector_status text);
alter table private.hub_kpi_prepared_fuel_state enable row level security;
revoke all on private.hub_kpi_prepared_fuel_state from public,anon,authenticated;
do $patch$ declare definition text; needle text; replacement text; begin
 select pg_get_functiondef(oid) into definition from pg_proc where proname='hub_kpi_run_report_jobs_v1' and pronamespace='private'::regnamespace;
 needle:='insert into private.hub_kpi_prepared_hub_objects select generation,t.* from public.hub_objects t where tenant_id=job.tenant_id and object_type=''Vehicle'';';
 replacement:='insert into private.hub_kpi_prepared_hub_objects select generation,t.* from public.hub_objects t where tenant_id=job.tenant_id and object_type in (''Vehicle'',''FuelTransaction'');
 insert into private.hub_kpi_prepared_fuel_reviews select generation,t.* from public.kpi_bsmart_cost_reviews t where t.tenant_id=job.tenant_id;
 insert into private.hub_kpi_prepared_fuel_state(generation_id,last_connector_success,connector_status) select generation,max(last_success_at),max(status) from public.hub_connections where tenant_id=job.tenant_id and connector_type=''piusi_bsmart'';';
 if position(needle in definition)=0 then raise exception 'Prepared worker changed: abort narrow fuel extension';end if;
 execute replace(definition,needle,replacement);
end $patch$;
-- Backfill current prepared generations once; subsequent snapshots are produced by the existing worker.
insert into private.hub_kpi_prepared_hub_objects select s.active_generation,o.* from private.hub_kpi_report_state s join public.hub_objects o on o.tenant_id=s.tenant_id and o.object_type='FuelTransaction' where s.active_generation is not null and not exists(select 1 from private.hub_kpi_prepared_hub_objects x where x.generation_id=s.active_generation and x.id=o.id);
insert into private.hub_kpi_prepared_fuel_reviews select s.active_generation,r.* from private.hub_kpi_report_state s join public.kpi_bsmart_cost_reviews r on r.tenant_id=s.tenant_id where s.active_generation is not null;
insert into private.hub_kpi_prepared_fuel_state(generation_id,last_connector_success,connector_status) select s.active_generation,max(c.last_success_at),max(c.status) from private.hub_kpi_report_state s left join public.hub_connections c on c.tenant_id=s.tenant_id and c.connector_type='piusi_bsmart' where s.active_generation is not null group by s.active_generation;

create or replace function private.hub_kpi_monthly_fuel_sources_v1(p_tenant_id uuid,p_year int,p_months int[],p_filters jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare generation uuid:=private.hub_kpi_active_report_generation_v1(p_tenant_id); output jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 perform private.hub_kpi_month_scope_v1(p_year,p_months);
 with facts as materialized(select * from private.hub_kpi_prepared_month_facts_v1(p_tenant_id,p_year,p_months,p_filters)),
 raw as materialized(select o.id,o.data,(o.data->>'transaction_date')::timestamp::date dt,
 v.id vehicle_id,public.hub_normalize_vehicle_registration(coalesce(v.data->>'registration_number',o.data->>'registration_number')) reg,
 nullif(o.data->>'quantity_liters','')::numeric liters,nullif(o.data->>'source_amount','')::numeric raw_cost,
 r.status review_status,r.corrected_cost_sek
 from private.hub_kpi_prepared_hub_objects o
 left join private.hub_kpi_prepared_hub_objects v on v.generation_id=generation and v.tenant_id=p_tenant_id and v.object_type='Vehicle' and v.id::text=o.data->>'vehicle_id'
 left join private.hub_kpi_prepared_fuel_reviews r on r.generation_id=generation and r.tenant_id=p_tenant_id and r.hub_object_id=o.id
 where o.generation_id=generation and o.tenant_id=p_tenant_id and o.object_type='FuelTransaction' and o.data->>'source_system'='piusi_bsmart'
 and (o.data->>'transaction_date')::timestamp::date between make_date(p_year,9,1) and make_date(p_year+1,8,31)
 and extract(month from (o.data->>'transaction_date')::timestamp)::int=any(p_months)),
 mapped as materialized(select f.*,c.center,c.business_group,
 case when review_status='rejected' then null when review_status='approved' then corrected_cost_sek when liters>0 and raw_cost>0 and raw_cost/liters between 5 and 40 then raw_cost end accepted_cost,
 case when review_status='approved' then 'approved' when review_status='rejected' then 'excluded' when liters>0 and raw_cost>0 and raw_cost/liters between 5 and 40 then 'provisional' else 'manual_review' end price_status
 from raw f left join lateral(select case when count(distinct cost_center)=1 then max(cost_center) end center,
 case when count(distinct business_group)=1 then max(business_group) end business_group
 from private.hub_kpi_prepared_kpi_project_classification_periods c where c.generation_id=generation and c.tenant_id=p_tenant_id and f.reg=any(c.registrations) and c.valid_from<=f.dt and (c.valid_to is null or c.valid_to>=f.dt)) c on true),
 scoped as materialized(select * from mapped f where f.vehicle_id is not null
 and (not(p_filters?'cost_center') or f.center=any(string_to_array(p_filters->>'cost_center',',')))
 and (not(p_filters?'group') or f.business_group=any(string_to_array(p_filters->>'group',',')))
 and (not(p_filters?'vehicle') or f.reg=p_filters->>'vehicle')
 and (not(p_filters?'project') or exists(select 1 from private.hub_kpi_prepared_kpi_project_classification_periods c where c.generation_id=generation and c.tenant_id=p_tenant_id and c.project_reference=p_filters->>'project' and f.reg=any(c.registrations) and c.valid_from<=f.dt and (c.valid_to is null or c.valid_to>=f.dt)))
 and (not(p_filters?'unit') or p_filters->>'unit'='vehicle:'||f.reg or exists(select 1 from private.hub_kpi_prepared_kpi_unit_periods u where u.generation_id=generation and u.tenant_id=p_tenant_id and u.unit_id::text=p_filters->>'unit' and u.valid_from<=f.dt and (u.valid_to is null or u.valid_to>=f.dt) and coalesce((u.payload->>'enabled')::boolean,false) and u.payload->'registrations'?f.reg))),
 piusi_periods as(select distinct extract(month from dt)::int m from raw),
 next_fuel as materialized(select f.*,not(account='5360' and extract(month from occurred_on)::int in(select m from piusi_periods)) include_cost from facts f where kind='cost' and category='fuel'),
 combined as(select 'Piusi' source,id::text id,dt,reg vehicle,accepted_cost amount,liters,price_status,data->>'product_name' product from scoped
 union all select 'NEXT',fact_id,occurred_on,vehicle,amount,null,'imported',coalesce(original->>'Kontobeskrivning',description) from next_fuel where include_cost),
 totals as(select count(*) rows,round(sum(amount),2) cost,round(sum(liters),2) liters,
 count(*) filter(where source='Piusi' and price_status='manual_review') review_rows,
 count(*) filter(where source='Piusi' and price_status='provisional') provisional_rows from combined)
 select jsonb_build_object('total_cost',case when rows>0 then cost end,'piusi_cost',(select round(sum(accepted_cost),2) from scoped),'piusi_liters',(select round(sum(liters) filter(where liters>0),2) from scoped),
 'next_cost',(select round(sum(amount),2) from next_fuel where include_cost),'next_tank_purchase_excluded',(select round(coalesce(sum(amount),0),2) from next_fuel where not include_cost),
 'piusi_rows',(select count(*) from scoped),'review_rows',review_rows,'provisional_rows',provisional_rows,
 'unclassified_rows',(select count(*) from mapped where vehicle_id is null or center is null),
 'last_transaction_at',(select max(dt) from scoped),'source_state',(select to_jsonb(s)-'generation_id' from private.hub_kpi_prepared_fuel_state s where s.generation_id=generation),
 'basis','Piusi: godkända/rimlighetskontrollerade tankningsbelopp (preliminära). NEXT: övriga bränslekostnader. Konto 5360 egen tank undantas under månader med Piusi-underlag och visas som avstämning. Okopplade/ogiltiga tankningar hålls utanför beloppen.',
 'vehicles',coalesce((select jsonb_agg(x order by x.vehicle) from(select vehicle,round(sum(amount),2) fuel,round(sum(liters),2) liters from combined group by vehicle)x),'[]'::jsonb),
 'transactions',coalesce((select jsonb_agg(to_jsonb(c) order by dt,id) from combined c),'[]'::jsonb)) into output from totals;
 return output;
end $$;
revoke all on function private.hub_kpi_monthly_fuel_sources_v1(uuid,int,int[],jsonb) from public,anon,authenticated;
create or replace function private.hub_kpi_transport_period_report_v1(p_tenant_id uuid,p_year int,p_months int[],p_filters jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare output jsonb; fuel_report jsonb; operations jsonb; revenue numeric; total_cost numeric; vehicles jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 with facts as materialized(select * from private.hub_kpi_prepared_month_facts_v1(p_tenant_id,p_year,p_months,p_filters)),
 totals as(select count(*) filter(where kind='revenue') revenue_rows,count(*) filter(where kind='cost') cost_rows,
 sum(amount) filter(where kind='revenue') invoiced_revenue,
 sum(amount) filter(where kind='revenue') recorded_revenue,sum(amount) filter(where kind='cost') cost,
 sum(amount) filter(where kind='cost' and source='TransPA') estimated_payroll,
 sum(amount) filter(where kind='cost' and category='fuel') fuel,
 count(*) filter(where kind='cost' and category='fuel') fuel_rows,
 count(*) filter(where kind='cost' and category='fuel' and concat_ws(' ',description,original->>'Kontobeskrivning',original->>'Verifikationstext') !~* '\mdiesel\M') non_diesel_rows,
 count(distinct extract(month from occurred_on)) filter(where kind='revenue') revenue_months,
 count(distinct extract(month from occurred_on)) filter(where kind='cost') cost_months from facts),
 vehicles as(select 'vehicle:'||vehicle key,case when vehicle in ('LASTBIL','INHYRDLASTBIL') then 'Inhyrda bilar' else vehicle end label,vehicle,
 round(coalesce(sum(amount) filter(where kind='revenue'),0),2) invoiced_revenue,
 round(coalesce(sum(amount) filter(where kind='revenue'),0),2) recorded_revenue,
 round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,
 round(coalesce(sum(amount) filter(where kind='cost' and category='fuel'),0),2) fuel,
 bool_or(vehicle in ('LASTBIL','INHYRDLASTBIL')) hired
 from facts where vehicle is not null and vehicle not in ('Ej fördelat','unassigned','')
 group by vehicle),
 fleet as(select count(*) filter(where not hired and recorded_revenue<>0) active_vehicles from vehicles)
 select jsonb_build_object('metrics',jsonb_build_array(
 jsonb_build_object('key','revenue','label','Fakturerad omsättning','value',case when revenue_rows>0 then round(coalesce(invoiced_revenue,0),2) end,'unit','kr','status',case when revenue_rows=0 then 'missing' when revenue_months<cardinality(p_months) then 'partial' else 'source' end,'basis','Rapportregel godkänd 2026-10-06: alla registrerade intäkter räknas som fakturerade. Perioden följer artikeldatum. Originalstatus behålls. Ej avstämt mot Fortnox.'),
 jsonb_build_object('key','result','label','Resultat','value',case when revenue_rows>0 and cost_rows>0 then round(coalesce(invoiced_revenue,0)-cost,2) end,'unit','kr','status',case when revenue_rows=0 or cost_rows=0 then 'missing' when revenue_months<cardinality(p_months) or cost_months<cardinality(p_months) then 'partial' else 'estimate' end,'basis','Preliminärt: fakturerade Workify-intäkter minus NEXT-kostnader och TransPA-personalschablon. Inte bokfört Fortnox-resultat.'),
 jsonb_build_object('key','revenue_per_truck','label','Intäkt per lastbil','value',case when active_vehicles>0 and revenue_rows>0 then round(coalesce(invoiced_revenue,0)/active_vehicles,2) end,'unit','kr','status',case when active_vehicles=0 or revenue_rows=0 then 'missing' else 'estimate' end,'basis','Fakturerad omsättning / antal egna intäktsbärande fordon i perioden. Inhyrdas samlingsenhet ingår i intäkten men inte i antalet. Fullständigt lastbilsbestånd behöver verifieras.'),
 jsonb_build_object('key','vehicle_utilization','label','Beläggningsgrad fordon','value',null,'unit','%','status','missing','basis','Debiterbar fordonstid / tillgänglig fordonstid. Verifierad debiterbar tid saknas. Rapporterad TransPA-tid visas separat.'),
 jsonb_build_object('key','diesel_share','label','Dieselkostnader / omsättning','value',case when fuel_rows>0 and non_diesel_rows=0 and invoiced_revenue<>0 then round(fuel/invoiced_revenue*100,2) end,'unit','%','status',case when fuel_rows>0 and non_diesel_rows=0 and invoiced_revenue<>0 then 'source' else 'missing' end,'basis','Dieselkostnad / fakturerad omsättning. Visas endast när samtliga bränslerader uttryckligen är diesel; övrigt drivmedel redovisas separat.'),
 jsonb_build_object('key','driver_billing','label','Debiteringsgrad chaufförer','value',null,'unit','%','status','missing','basis','Debiterbar chaufförstid / arbetad tid. Verifierad debiterbar tid per chaufför saknas; intäktskopplad TransPA-tid är en separat indikator.')),
 'recorded_revenue',round(recorded_revenue,2),'uninvoiced_revenue',round(recorded_revenue-coalesce(invoiced_revenue,0),2),
 'cost',round(cost,2),'estimated_payroll',round(estimated_payroll,2),'fuel',round(fuel,2),
 'fuel_share',round(fuel/nullif(invoiced_revenue,0)*100,2),'active_vehicle_count',active_vehicles,
 'coverage',jsonb_build_object('requested_months',p_months,'revenue_months',revenue_months,'cost_months',cost_months),
 'vehicles',coalesce((select jsonb_agg(to_jsonb(v) order by v.label) from vehicles v),'[]'::jsonb)) into output from totals cross join fleet;
 fuel_report:=private.hub_kpi_monthly_fuel_sources_v1(p_tenant_id,p_year,p_months,p_filters);
 operations:=private.hub_kpi_prepared_snapshot_v1(p_tenant_id,p_year,p_months,p_filters);
 revenue:=(output->>'recorded_revenue')::numeric;
 total_cost:=case when output->>'cost' is not null then (output->>'cost')::numeric-coalesce((output->>'fuel')::numeric,0)+coalesce((fuel_report->>'total_cost')::numeric,0) end;
 select coalesce(jsonb_agg(v||jsonb_build_object('fuel',coalesce((f->>'fuel')::numeric,0),'fuel_liters',(f->>'liters')::numeric,'cost',(v->>'cost')::numeric-(v->>'fuel')::numeric+coalesce((f->>'fuel')::numeric,0)) order by v->>'label'),'[]'::jsonb) into vehicles from jsonb_array_elements(output->'vehicles') v left join jsonb_array_elements(fuel_report->'vehicles') f on f->>'vehicle'=v->>'vehicle';
 output:=output||jsonb_build_object('fuel_sources',fuel_report,'fuel',(fuel_report->>'total_cost')::numeric,'fuel_share',round((fuel_report->>'total_cost')::numeric/nullif(revenue,0)*100,2),'cost',total_cost,'vehicles',vehicles,
 'time',jsonb_build_object('reported_vehicle_hours',operations#>'{transpa_vehicle_time,reported_hours}','available_vehicle_hours',operations#>'{transpa_vehicle_time,available_hours}','worked_driver_hours',operations#>'{driver_productivity,total_hours}','revenue_linked_driver_hours',operations#>'{driver_productivity,productive_hours}','unclassified_driver_hours',operations#>'{driver_productivity,unclassified_hours}',
 'vehicles',operations#>'{transpa_vehicle_time,vehicles}','drivers',operations#>'{driver_productivity,drivers}'));
 output:=jsonb_set(output,'{metrics,1,value}',coalesce(to_jsonb(round(revenue-total_cost,2)),'null'::jsonb));
 output:=jsonb_set(output,'{metrics,1,basis}',to_jsonb('Registrerade intäkter minus NEXT-kostnader och TransPA-schablon. Bränsledelen ersätts med Piusi + NEXT utan dubbelt konto 5360. Preliminärt, inte Fortnox-bokslut.'::text));
 output:=jsonb_set(output,'{metrics,3}',jsonb_build_object('key','vehicle_utilization','label','Beläggningsgrad fordon – TransPA','unit','%','value',operations#>'{transpa_vehicle_time,utilization}','status','estimate','basis','Rapporterad fordonstid från TransPA / vardagskapacitet enligt Hub-inställning. Indikator, inte verifierad debiterbar tid.'));
 output:=jsonb_set(output,'{metrics,4}',jsonb_build_object('key','diesel_share','label','Bränslekostnad / omsättning','unit','%','value',round((fuel_report->>'total_cost')::numeric/nullif(revenue,0)*100,2),'status',case when fuel_report->>'total_cost' is null then 'missing' when (fuel_report->>'review_rows')::int>0 or (fuel_report->>'unclassified_rows')::int>0 then 'partial' else 'estimate' end,'basis',fuel_report->>'basis'));
 output:=jsonb_set(output,'{metrics,5}',jsonb_build_object('key','driver_billing','label','Debiteringsgrad chaufförer – TransPA-indikator','unit','%','value',operations#>'{driver_productivity,productive_percent}','status','estimate','basis','Intäktskopplad TransPA-tid / arbetad TransPA-tid. Koppling till intäktsdag är en indikator, inte verifierade fakturerade timmar.'));
 if (fuel_report->>'review_rows')::int>0 or (fuel_report->>'unclassified_rows')::int>0 then output:=jsonb_set(output,'{metrics,1,status}','"partial"'::jsonb);end if;
 return output;
end $$;
revoke all on function private.hub_kpi_transport_period_report_v1(uuid,int,int[],jsonb) from public,anon,authenticated;

