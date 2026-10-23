CREATE OR REPLACE FUNCTION private.hub_kpi_next_time_period_v1(p_tenant uuid, p_year integer, p_months integer[], p_filters jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare g uuid;months integer[];answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read')then raise exception 'KPI access required'using errcode='42501';end if;
 months:=private.hub_kpi_month_scope_v1(p_year,p_months);
 g:=private.hub_kpi_active_report_generation_v1(p_tenant);
 if not exists(select 1 from private.hub_kpi_prepared_kpi_import_rows r where r.tenant_id=p_tenant and r.generation_id=g
  and r.data_kind='next_historical_time'and r.occurred_on between make_date(p_year,9,1)and make_date(p_year+1,8,31)
  and extract(month from r.occurred_on)::int=any(months))then
  return jsonb_build_object('available',false,'rows',0,'project_hours',null,'workshop_hours',null,'absence_hours',0,'supplement_hours',0,
   'review_rows',0,'unmapped_unit_hours',0,'workshop_hours_without_cost_reference',0,'workshop_cost_references','[]'::jsonb,'units','[]'::jsonb,
   'basis','Publicerad NEXT-tid saknas för perioden. Saknat underlag visas inte som noll arbetade timmar.');
 end if;

 with source_rows as materialized(
  select r.*,b.status batch_status,
   (lower(trim(coalesce(r.source_data->>'Godkänd','')))in('true','ja','1')or r.source_data#>>'{_humla_time_approval,approved}'='true') approved,
   coalesce(r.source_data,'{}')-array['Godkännandedatum','Godkänd av','Godkänd','Fakturadatum','_humla_time_approval'] fingerprint
  from private.hub_kpi_prepared_kpi_import_rows r
  join public.kpi_import_batches b on b.tenant_id=r.tenant_id and b.id=r.batch_id
  where r.tenant_id=p_tenant and r.generation_id=g and r.data_kind='next_historical_time' and b.status='completed'
   and r.occurred_on between make_date(p_year,9,1)and make_date(p_year+1,8,31)
   and extract(month from r.occurred_on)::int=any(months)
 ), occurrences as(
  select *,row_number()over(partition by batch_id,fingerprint order by row_number,id) occurrence from source_rows
 ), copies as(
  select *,row_number()over(partition by fingerprint,occurrence order by approved desc,is_valid desc,created_at desc,id) copy_rank from occurrences
 ), project_keys as materialized(
  select k.identity_value,(array_agg(distinct k.object_id))[1] object_id
  from public.hub_identity_keys k where k.tenant_id=p_tenant and k.identity_type='next_project_number'and k.confidence=1
  group by k.identity_value having count(distinct k.object_id)=1
 ), unit_members as materialized(
  select u.id unit_id,v.period,m.member
  from public.hub_objects u cross join lateral jsonb_array_elements(coalesce(u.data->'periods','[]'))v(period)
   cross join lateral jsonb_array_elements(coalesce(v.period->'members','[]'))m(member)
  where u.tenant_id=p_tenant and u.object_type='EconomicUnit'and coalesce((v.period->>'enabled')::boolean,false)
 ), resolved as materialized(
  select r.*,k.object_id project_id,
   coalesce(nullif(trim(r.cost_center),''),nullif(trim(r.source_data->>'Kostnadsställe nr'),''),c.cost_center,'unclassified') target_center,
   c.business_group,
   coalesce(nullif(upper(trim(r.vehicle_registration)),''),case when cardinality(c.registrations)=1 then c.registrations[1]end) registration,
   case when u.n=1 then u.unit_id end source_unit,
   coalesce(r.project_reference='99999' or lower(trim(r.source_data->>'Projektnamn'))='frånvaro',false) absence,
   upper(trim(coalesce(r.source_data->>'Tidkod','')))~'^OB' supplement,
   upper(trim(coalesce(r.source_data->>'Roll',r.description,'')))='REP' workshop
  from copies r left join project_keys k on k.identity_value=r.project_reference
  left join lateral(
   select c.* from private.hub_kpi_prepared_kpi_project_classification_periods c
   where c.tenant_id=p_tenant and c.generation_id=g and c.project_reference=r.project_reference
    and c.valid_from<=r.occurred_on and(c.valid_to is null or c.valid_to>=r.occurred_on)
   order by c.valid_from desc,c.id limit 1
  )c on true
  left join lateral(
   select count(distinct um.unit_id)n,(array_agg(distinct um.unit_id))[1]unit_id from unit_members um
   where um.member->>'object_id'=k.object_id::text and um.member->>'kind'='project'
    and(um.period->>'valid_from')::date<=r.occurred_on
    and(nullif(um.period->>'valid_to','')is null or(um.period->>'valid_to')::date>=r.occurred_on)
  )u on true
  where copy_rank=1
 ), collected as(
  select r.*,coalesce(case when rel.n=1 then rel.unit_id end,r.source_unit,(select (array_agg(o.id))[1]from public.hub_objects o where o.tenant_id=p_tenant and o.object_type='EconomicUnit'and o.data->>'report_fallback'='unresolved'having count(*)=1)) unit_id
  from resolved r left join lateral(
   select count(distinct a.to_object_id)n,(array_agg(distinct a.to_object_id))[1]unit_id
   from public.hub_object_relations a where a.tenant_id=p_tenant and a.from_object_id=r.source_unit
   and a.relation_type='reports_in'and a.status='active'and a.confidence=1
   and(a.valid_from is null or r.occurred_on>=(a.valid_from at time zone 'Europe/Stockholm')::date)
   and(a.valid_to is null or r.occurred_on<=(a.valid_to at time zone 'Europe/Stockholm')::date)
  )rel on true
 ), scoped as materialized(
  select * from collected r
  where(not(p_filters?'cost_center')or r.target_center=any(string_to_array(p_filters->>'cost_center',',')))
   and(not(p_filters?'project')or r.project_reference=p_filters->>'project')
   and(not(p_filters?'unit')or r.unit_id::text=p_filters->>'unit' or p_filters->>'unit'='vehicle:'||r.registration)
   and(not(p_filters?'vehicle')or r.registration=p_filters->>'vehicle')
   and(not(p_filters?'group')or r.business_group=any(string_to_array(p_filters->>'group',',')))
   and not exists(select 1 from private.hub_kpi_project_exclusions e where e.tenant_id=p_tenant and e.enabled
    and(e.project_id=r.project_id or e.economic_unit_id=r.source_unit))
 ), valid_work as materialized(
  select * from scoped where approved and is_valid and paid_hours>=0 and not absence and not supplement
 ), repair_projects as(
  select project_reference project,project_id,date_trunc('month',occurred_on)::date month_start,sum(paid_hours)hours
  from valid_work where workshop group by 1,2,3
 ), repair_debits as(
  select f.project,date_trunc('month',f.occurred_on)::date month_start,sum(f.amount)amount,count(*)rows
  from private.hub_kpi_prepared_month_facts_v1(p_tenant,p_year,p_months,p_filters)f
  where f.source='NEXT'and f.kind='cost'and f.category='service_repair'and f.account='4630'
   and(concat_ws(' ',f.description,f.original->>'Verifikationstext')ilike '%verkstad%'or f.original->>'Verifikation nr'~'^AO[.][0-9]{4}-[0-9]{2}$')
  group by 1,2
 ), estimates as(
 select f.project,date_trunc('month',f.occurred_on)::date month_start,sum(f.amount) estimated_repair_cost
 from private.hub_kpi_prepared_month_facts_v1(p_tenant,p_year,p_months,p_filters)f
 where f.kind='cost'and f.category='service_repair'and f.source='Verkstadsschablon'group by 1,2
 ), repair_evidence as(
  select p.*,d.amount posted_repair_debit,coalesce(d.rows,0)cost_rows,e.estimated_repair_cost from repair_projects p left join repair_debits d using(project,month_start)left join estimates e using(project,month_start)
 ), units as(
  select unit_id,sum(paid_hours)filter(where not workshop)project_hours,sum(paid_hours)filter(where workshop)workshop_hours
  from valid_work where unit_id is not null group by unit_id
 )select jsonb_build_object('available',exists(select 1 from scoped),'rows',(select count(*)from valid_work),
  'project_hours',case when exists(select 1 from scoped)then coalesce((select sum(paid_hours)from valid_work where not workshop),0)end,
  'workshop_hours',case when exists(select 1 from scoped)then coalesce((select sum(paid_hours)from valid_work where workshop),0)end,
  'absence_hours',(select coalesce(sum(paid_hours),0)from scoped where approved and is_valid and absence),
  'supplement_hours',(select coalesce(sum(paid_hours),0)from scoped where approved and is_valid and not absence and supplement),
  'review_rows',(select count(*)from scoped where not approved or not is_valid or paid_hours is null or paid_hours<0),
  'unmapped_unit_hours',(select coalesce(sum(paid_hours),0)from valid_work where source_unit is null),
  'workshop_hours_without_cost_reference',(select coalesce(sum(hours),0)from repair_evidence where cost_rows=0),
  'workshop_estimated_repair_cost',(select coalesce(sum(estimated_repair_cost),0)from repair_evidence),
  'workshop_cost_references',coalesce((select jsonb_agg(to_jsonb(e)order by e.month_start,e.project)from repair_evidence e),'[]'::jsonb),
  'units',coalesce((select jsonb_agg(jsonb_build_object('key',unit_id,'project_hours',coalesce(project_hours,0),'workshop_hours',coalesce(workshop_hours,0)))from units),'[]'::jsonb),
  'basis','Godkända NEXT-tidrader på mottagande kostnadsställe/projekt. Frånvaro och OB-tillägg ingår inte i arbetad tid. Identiska återimporter räknas en gång; upprepade poster i samma fil behålls. Projekttid och verkstadstid visas separat från TransPA och summeras inte med chaufförstiden. Verkstadstid hör till Service & reparation; befintlig NEXT-verkstadsdebitering räknas endast en gång. Endast godkända kostnadsprofiler skapar preliminär schablonkostnad för tid utan verkstadsdebitering. Den ersätts när verklig NEXT-debitering finns. Historisk arbetstid saknar rolluppgift och visas som projekttid; ingen verkstadsroll antas från personens namn.')into answer;
 return answer;
end $function$;

CREATE OR REPLACE FUNCTION private.hub_kpi_transport_period_report_v1(p_tenant_id uuid, p_year integer, p_months integer[], p_filters jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare next_time jsonb;internal_data jsonb;workshop_debit numeric;output jsonb; fuel_report jsonb; operations jsonb; revenue numeric; total_cost numeric; vehicles jsonb; economic_units jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 with facts as materialized(select * from private.hub_kpi_prepared_month_facts_v1(p_tenant_id,p_year,p_months,p_filters)),
 totals as(select count(*) filter(where kind='revenue') revenue_rows,count(*) filter(where kind='cost') cost_rows,
 sum(amount) filter(where kind='revenue') invoiced_revenue,
 sum(amount) filter(where kind='revenue') recorded_revenue,sum(amount) filter(where kind='cost') cost,
 sum(amount) filter(where kind='cost' and(source='TransPA'or(source='NEXT-schablon'and category='personnel'))) estimated_payroll,
 sum(amount)filter(where source='NEXT'and kind='cost'and category='service_repair'and account='4630'and(concat_ws(' ',description,original->>'Verifikationstext')ilike '%verkstad%'or original->>'Verifikation nr'~'^AO[.][0-9]{4}-[0-9]{2}$')) workshop_repair_debit,
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
 fleet as(select case when exists(select 1 from private.hub_kpi_material_separation_settings where tenant_id=p_tenant_id and enabled) then (select count(distinct vehicle) from facts where kind='revenue' and amount<>0 and vehicle not in('LASTBIL','Ej fördelat')) else count(*) filter(where not hired and recorded_revenue<>0) end active_vehicles from vehicles)
 select jsonb_build_object('metrics',jsonb_build_array(
 jsonb_build_object('key','revenue','label','Fakturerad omsättning','value',case when revenue_rows>0 then round(coalesce(invoiced_revenue,0),2) end,'unit','kr','status',case when revenue_rows=0 then 'missing' when revenue_months<cardinality(p_months) then 'partial' else 'source' end,'basis','Rapportregel godkänd 2026-10-06: alla registrerade intäkter räknas som fakturerade. Perioden följer artikeldatum. Originalstatus behålls. Ej avstämt mot Fortnox.'),
 jsonb_build_object('key','result','label','Resultat','value',case when revenue_rows>0 and cost_rows>0 then round(coalesce(invoiced_revenue,0)-cost,2) end,'unit','kr','status',case when revenue_rows=0 or cost_rows=0 then 'missing' when revenue_months<cardinality(p_months) or cost_months<cardinality(p_months) then 'partial' else 'estimate' end,'basis','Preliminärt: fakturerade Workify-intäkter minus NEXT-kostnader samt TransPA- och godkänd historisk NEXT-personalschablon efter avräkning av motsvarande NEXT-arbetstidskostnad. Inte bokfört Fortnox-resultat.'),
 jsonb_build_object('key','revenue_per_truck','label','Intäkt per lastbil','value',case when active_vehicles>0 and revenue_rows>0 then case when exists(select 1 from private.hub_kpi_material_separation_settings where tenant_id=p_tenant_id and enabled) then round((select coalesce(sum(amount),0) from facts where kind='revenue' and vehicle not in('LASTBIL','INHYRDLASTBIL','Ej fördelat',''))/active_vehicles,2) else round(coalesce(invoiced_revenue,0)/active_vehicles,2) end end,'unit','kr','status',case when active_vehicles=0 or revenue_rows=0 then 'missing' else 'estimate' end,'basis','Intäkter på egna intäktsbärande fordon / antal fordon när materialuppdelning är aktiv. Projektintäkter och inhyrda räknas då inte med. Fullständigt lastbilsbestånd behöver verifieras.'),
 jsonb_build_object('key','vehicle_utilization','label','Beläggningsgrad fordon','value',null,'unit','%','status','missing','basis','Debiterbar fordonstid / tillgänglig fordonstid. Verifierad debiterbar tid saknas. Rapporterad TransPA-tid visas separat.'),
 jsonb_build_object('key','diesel_share','label','Dieselkostnader / omsättning','value',case when fuel_rows>0 and non_diesel_rows=0 and invoiced_revenue<>0 then round(fuel/invoiced_revenue*100,2) end,'unit','%','status',case when fuel_rows>0 and non_diesel_rows=0 and invoiced_revenue<>0 then 'source' else 'missing' end,'basis','Dieselkostnad / fakturerad omsättning. Visas endast när samtliga bränslerader uttryckligen är diesel; övrigt drivmedel redovisas separat.'),
 jsonb_build_object('key','driver_billing','label','Debiteringsgrad chaufförer','value',null,'unit','%','status','missing','basis','Debiterbar chaufförstid / arbetad tid. Verifierad debiterbar tid per chaufför saknas; intäktskopplad TransPA-tid är en separat indikator.')),
 'recorded_revenue',round(recorded_revenue,2),'uninvoiced_revenue',round(recorded_revenue-coalesce(invoiced_revenue,0),2),
 'cost',round(cost,2),'workshop_repair_debit',round(coalesce(workshop_repair_debit,0),2),'estimated_payroll',round(estimated_payroll,2),'fuel',round(fuel,2),
 'fuel_share',round(fuel/nullif(invoiced_revenue,0)*100,2),'active_vehicle_count',active_vehicles,
 'coverage',jsonb_build_object('requested_months',p_months,'revenue_months',revenue_months,'cost_months',cost_months),
 'vehicles',coalesce((select jsonb_agg(to_jsonb(v) order by v.label) from vehicles v),'[]'::jsonb)) into output from totals cross join fleet;
 fuel_report:=private.hub_kpi_monthly_fuel_sources_v1(p_tenant_id,p_year,p_months,p_filters);
 operations:=private.hub_kpi_prepared_snapshot_v1(p_tenant_id,p_year,p_months,p_filters);
 revenue:=(output->>'recorded_revenue')::numeric;
 total_cost:=case when output->>'cost' is not null then (output->>'cost')::numeric-coalesce((output->>'fuel')::numeric,0)+coalesce((fuel_report->>'total_cost')::numeric,0) end;
 select coalesce(jsonb_agg(v||jsonb_build_object('fuel',coalesce((f->>'fuel')::numeric,0),'fuel_liters',(f->>'liters')::numeric,'cost',(v->>'cost')::numeric-(v->>'fuel')::numeric+coalesce((f->>'fuel')::numeric,0)) order by v->>'label'),'[]'::jsonb) into vehicles from jsonb_array_elements(output->'vehicles') v left join jsonb_array_elements(fuel_report->'vehicles') f on f->>'vehicle'=v->>'vehicle';
 select coalesce(jsonb_agg(jsonb_build_object('key',u->'key','label',u->'label','revenue',u->'revenue','worked_hours',u->'worked_hours','occupied_hours',u->'occupied_hours','available_hours',u->'available_hours','fuel',coalesce((f->>'fuel')::numeric,0),'fuel_liters',(f->>'liters')::numeric,'cost',(u->>'cost')::numeric-coalesce((u#>>'{cost_categories,fuel}')::numeric,0)+coalesce((f->>'fuel')::numeric,0)) order by u->>'label'),'[]'::jsonb) into economic_units from jsonb_array_elements(operations->'economic_units') u left join jsonb_array_elements(fuel_report->'units') f on f->>'unit_key'=u->>'key';
 output:=output||jsonb_build_object('economic_units',economic_units,'fuel_sources',fuel_report,'fuel',(fuel_report->>'total_cost')::numeric,'fuel_share',round((fuel_report->>'total_cost')::numeric/nullif(revenue,0)*100,2),'cost',total_cost,'vehicles',vehicles,
 'time',jsonb_build_object('reported_vehicle_hours',operations#>'{transpa_vehicle_time,reported_hours}','available_vehicle_hours',operations#>'{transpa_vehicle_time,available_hours}','worked_driver_hours',operations#>'{driver_productivity,total_hours}','revenue_linked_driver_hours',operations#>'{driver_productivity,productive_hours}','unclassified_driver_hours',operations#>'{driver_productivity,unclassified_hours}',
 'vehicles',operations#>'{transpa_vehicle_time,vehicles}','drivers',operations#>'{driver_productivity,drivers}'));
 output:=jsonb_set(output,'{metrics,1,value}',coalesce(to_jsonb(round(revenue-total_cost,2)),'null'::jsonb));
 output:=jsonb_set(output,'{metrics,1,basis}',to_jsonb('Registrerade intäkter minus NEXT-kostnader och TransPA-schablon. Bränsledelen ersätts med Piusi + NEXT utan dubbelt konto 5360. Preliminärt, inte Fortnox-bokslut.'::text));
 output:=jsonb_set(output,'{metrics,3}',jsonb_build_object('key','vehicle_utilization','label','Beläggningsgrad fordon – TransPA','unit','%','value',operations#>'{transpa_vehicle_time,utilization}','status','estimate','basis','Rapporterad fordonstid från TransPA / vardagskapacitet enligt Hub-inställning. Indikator, inte verifierad debiterbar tid.'));
 output:=jsonb_set(output,'{metrics,4}',jsonb_build_object('key','diesel_share','label','Bränslekostnad / omsättning','unit','%','value',round((fuel_report->>'total_cost')::numeric/nullif(revenue,0)*100,2),'status',case when fuel_report->>'total_cost' is null then 'missing' when (fuel_report->>'review_rows')::int>0 or (fuel_report->>'unclassified_rows')::int>0 then 'partial' else 'estimate' end,'basis',fuel_report->>'basis'));
 output:=jsonb_set(output,'{metrics,5}',jsonb_build_object('key','driver_billing','label','Debiteringsgrad chaufförer – TransPA-indikator','unit','%','value',operations#>'{driver_productivity,productive_percent}','status','estimate','basis','Intäktskopplad TransPA-tid / arbetad TransPA-tid. Koppling till intäktsdag är en indikator, inte verifierade fakturerade timmar.'));
 if (fuel_report->>'review_rows')::int>0 or (fuel_report->>'unclassified_rows')::int>0 then output:=jsonb_set(output,'{metrics,1,status}','"partial"'::jsonb);end if;

 -- monthly_next_time_v1: display sources separately; do not alter financial totals.
 next_time:=private.hub_kpi_next_time_period_v1(p_tenant_id,p_year,p_months,p_filters);
 internal_data:=private.hub_kpi_internal_overview_v1(p_tenant_id,p_year,p_months,p_filters);
 workshop_debit:=(output->>'workshop_repair_debit')::numeric;
 output:=output||jsonb_build_object('next_time',next_time,'internal_revenue',coalesce((internal_data->>'total')::numeric,0)+coalesce((internal_data->>'pending_amount')::numeric,0),
  'internal_invoiced_source_revenue',(internal_data->>'total')::numeric,'internal_pending_source_revenue',(internal_data->>'pending_amount')::numeric,
  'internal_revenue_basis','Varav intern debitering ingår redan i fakturerade intäkter. Samma rapportregel som totalen: alla registrerade intäkter, även rader med annan originalstatus, på kund Elleholms Maskin AB. Beloppet läggs inte till omsättningen igen.',
  'workshop_repair_debit',workshop_debit);
 select coalesce(jsonb_agg(u||jsonb_build_object('next_project_hours',n->'project_hours','next_workshop_hours',n->'workshop_hours')order by u->>'label'),'[]')into economic_units
 from jsonb_array_elements(output->'economic_units')u left join jsonb_array_elements(next_time->'units')n on n->>'key'=u->>'key';
 output:=jsonb_set(output,'{economic_units}',economic_units);
 output:=jsonb_set(output,'{metrics}',output->'metrics'||jsonb_build_array(jsonb_build_object(
  'key','internal_revenue','label','Varav intern debitering','unit','kr','value',output->'internal_revenue','status','source','basis',output->>'internal_revenue_basis')));

 return output;

end $function$

;
