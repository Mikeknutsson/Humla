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
 select coalesce(jsonb_agg(jsonb_build_object('key',u->'key','label',u->'label','children',u->'children','revenue',u->'revenue','worked_hours',u->'worked_hours','occupied_hours',u->'occupied_hours','available_hours',u->'available_hours','fuel',coalesce((f->>'fuel')::numeric,0),'fuel_liters',(f->>'liters')::numeric,'cost',(u->>'cost')::numeric-coalesce((u#>>'{cost_categories,fuel}')::numeric,0)+coalesce((f->>'fuel')::numeric,0)) order by u->>'label'),'[]'::jsonb) into economic_units from jsonb_array_elements(operations->'economic_units') u left join jsonb_array_elements(fuel_report->'units') f on f->>'unit_key'=u->>'key';
 output:=output||jsonb_build_object('economic_units',economic_units,'fuel_sources',fuel_report,'fuel',(fuel_report->>'total_cost')::numeric,'fuel_share',round((fuel_report->>'total_cost')::numeric/nullif(revenue,0)*100,2),'cost',total_cost,'vehicles',vehicles,
 'time',jsonb_build_object('reported_vehicle_hours',operations#>'{transpa_vehicle_time,reported_hours}','available_vehicle_hours',operations#>'{transpa_vehicle_time,available_hours}','worked_driver_hours',operations#>'{driver_productivity,total_hours}','revenue_linked_driver_hours',operations#>'{driver_productivity,productive_hours}','unclassified_driver_hours',operations#>'{driver_productivity,unclassified_hours}',
 'vehicles',operations#>'{transpa_vehicle_time,vehicles}','drivers',operations#>'{driver_productivity,drivers}'));
 output:=jsonb_set(output,'{metrics,1,value}',coalesce(to_jsonb(round(revenue-total_cost,2)),'null'::jsonb));
 output:=jsonb_set(output,'{metrics,1,basis}',to_jsonb('Registrerade intäkter minus NEXT-kostnader, TransPA-schablon och godkända NEXT-schabloner efter avräkning av motsvarande arbetskostnad. Bränsledelen ersätts med Piusi + NEXT utan dubbelt konto 5360. Preliminärt, inte Fortnox-bokslut.'::text));
 output:=jsonb_set(output,'{metrics,3}',jsonb_build_object('key','vehicle_utilization','label','Beläggningsgrad fordon','unit','%','value',operations#>'{transpa_vehicle_time,utilization}','status','estimate','basis','Arbetad fordonstid från TransPA + godkänd NEXT-projekttid efter överlappskontroll / vardagskapacitet. Endast fordon med positiva timmar i urvalet ingår.'));
 output:=jsonb_set(output,'{metrics,4}',jsonb_build_object('key','diesel_share','label','Bränslekostnad / omsättning','unit','%','value',round((fuel_report->>'total_cost')::numeric/nullif(revenue,0)*100,2),'status',case when fuel_report->>'total_cost' is null then 'missing' when (fuel_report->>'review_rows')::int>0 or (fuel_report->>'unclassified_rows')::int>0 then 'partial' else 'estimate' end,'basis',fuel_report->>'basis'));
 output:=jsonb_set(output,'{metrics,5}',jsonb_build_object('key','driver_billing','label','Debiteringsgrad chaufförer – TransPA-indikator','unit','%','value',operations#>'{driver_productivity,productive_percent}','status','estimate','basis','Intäktskopplad TransPA-tid / arbetad TransPA-tid. Koppling till intäktsdag är en indikator, inte verifierade fakturerade timmar.'));
 if (fuel_report->>'review_rows')::int>0 or (fuel_report->>'unclassified_rows')::int>0 then output:=jsonb_set(output,'{metrics,1,status}','"partial"'::jsonb);end if;

 -- monthly_next_time_v1: display sources separately; do not alter financial totals.
 next_time:=operations->'next_time';
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


 -- Shared worked time is already merged once in the operations projection.
 output:=output||jsonb_build_object('worked_time',operations->'worked_time');
 output:=jsonb_set(output,'{time,worked_hours}',coalesce(operations#>'{worked_time,worked_hours}','null'::jsonb));
 select coalesce(jsonb_agg(u||jsonb_build_object(
  'utilization',o->'utilization','available_hours',o->'available_hours',
  'cost_per_hour',round((u->>'cost')::numeric/nullif((u->>'worked_hours')::numeric,0),2),
  'revenue_per_hour',round((u->>'revenue')::numeric/nullif((u->>'worked_hours')::numeric,0),2))),'[]')
 into economic_units from jsonb_array_elements(output->'economic_units')u
 left join jsonb_array_elements(operations->'economic_units')o on o->>'key'=u->>'key';
 output:=jsonb_set(output,'{economic_units}',economic_units);
 select coalesce(jsonb_agg(v||jsonb_build_object('worked_hours',o->'worked_hours','available_hours',o->'available_hours','utilization',o->'utilization',
  'cost_per_hour',round((v->>'cost')::numeric/nullif((o->>'worked_hours')::numeric,0),2),
  'revenue_per_hour',round((v->>'recorded_revenue')::numeric/nullif((o->>'worked_hours')::numeric,0),2))),'[]')
 into vehicles from jsonb_array_elements(output->'vehicles')v
 left join jsonb_array_elements(operations->'vehicles')o on o->>'vehicle'=v->>'vehicle';
 output:=jsonb_set(output,'{vehicles}',vehicles);
 output:=jsonb_set(output,'{metrics}',output->'metrics'||jsonb_build_array(
  jsonb_build_object('key','cost_per_worked_hour','label','Fordonskostnad / arbetad timme','unit','kr/h',
   'value',(select round(sum((v->>'cost')::numeric)/nullif(sum((v->>'worked_hours')::numeric),0),2)from jsonb_array_elements(vehicles)v where(v->>'worked_hours')::numeric>0),
   'status','estimate','basis',operations#>>'{worked_time,basis}'),
  jsonb_build_object('key','revenue_per_worked_hour','label','Fordonsintäkt / arbetad timme','unit','kr/h',
   'value',(select round(sum((v->>'recorded_revenue')::numeric)/nullif(sum((v->>'worked_hours')::numeric),0),2)from jsonb_array_elements(vehicles)v where(v->>'worked_hours')::numeric>0),
   'status','estimate','basis',operations#>>'{worked_time,basis}')));

 return output;

end $function$;
-- Invalidate prior overview computations; future imports use the same functions.
update private.hub_kpi_report_state set correction_revision=correction_revision+1;
notify pgrst,'reload schema';
