-- Additive monthly delivery report. Reads the existing daily prepared generation.
create or replace function private.hub_kpi_transport_period_report_v1(p_tenant_id uuid,p_year int,p_months int[],p_filters jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare output jsonb;
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
 vehicles as(select coalesce(unit_id::text,'vehicle:'||vehicle) key,coalesce(unit_name,vehicle) label,
 round(coalesce(sum(amount) filter(where kind='revenue'),0),2) invoiced_revenue,
 round(coalesce(sum(amount) filter(where kind='revenue'),0),2) recorded_revenue,
 round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,
 round(coalesce(sum(amount) filter(where kind='cost' and category='fuel'),0),2) fuel,
 bool_or(vehicle in ('LASTBIL','INHYRDLASTBIL')) hired
 from facts where vehicle is not null and vehicle not in ('Ej fördelat','unassigned','')
 group by coalesce(unit_id::text,'vehicle:'||vehicle),coalesce(unit_name,vehicle)),
 fleet as(select count(*) filter(where not hired and recorded_revenue<>0) active_vehicles from vehicles)
 select jsonb_build_object('metrics',jsonb_build_array(
 jsonb_build_object('key','revenue','label','Fakturerad omsättning','value',case when revenue_rows>0 then round(coalesce(invoiced_revenue,0),2) end,'unit','kr','status',case when revenue_rows=0 then 'missing' when revenue_months<cardinality(p_months) then 'partial' else 'source' end,'basis','Rapportregel godkänd 2026-10-06: alla registrerade intäkter räknas som fakturerade. Perioden följer artikeldatum. Originalstatus behålls. Ej avstämt mot Fortnox.'),
 jsonb_build_object('key','result','label','Resultat','value',case when revenue_rows>0 and cost_rows>0 then round(coalesce(invoiced_revenue,0)-cost,2) end,'unit','kr','status',case when revenue_rows=0 or cost_rows=0 then 'missing' when revenue_months<cardinality(p_months) or cost_months<cardinality(p_months) then 'partial' else 'estimate' end,'basis','Preliminärt: fakturerade Workify-intäkter minus NEXT-kostnader och TransPA-personalschablon. Inte bokfört Fortnox-resultat.'),
 jsonb_build_object('key','revenue_per_truck','label','Intäkt per lastbil','value',case when active_vehicles>0 and revenue_rows>0 then round(coalesce(invoiced_revenue,0)/active_vehicles,2) end,'unit','kr','status',case when active_vehicles=0 or revenue_rows=0 then 'missing' else 'estimate' end,'basis','Fakturerad omsättning / antal egna intäktsbärande fordonsenheter i perioden. Inhyrdas samlingsenhet ingår i intäkten men inte i antalet. Fullständigt lastbilsbestånd behöver verifieras.'),
 jsonb_build_object('key','vehicle_utilization','label','Beläggningsgrad fordon','value',null,'unit','%','status','missing','basis','Debiterbar fordonstid / tillgänglig fordonstid. Verifierad debiterbar tid saknas. Rapporterad TransPA-tid visas separat.'),
 jsonb_build_object('key','diesel_share','label','Dieselkostnader / omsättning','value',case when fuel_rows>0 and non_diesel_rows=0 and invoiced_revenue<>0 then round(fuel/invoiced_revenue*100,2) end,'unit','%','status',case when fuel_rows>0 and non_diesel_rows=0 and invoiced_revenue<>0 then 'source' else 'missing' end,'basis','Dieselkostnad / fakturerad omsättning. Visas endast när samtliga bränslerader uttryckligen är diesel; övrigt drivmedel redovisas separat.'),
 jsonb_build_object('key','driver_billing','label','Debiteringsgrad chaufförer','value',null,'unit','%','status','missing','basis','Debiterbar chaufförstid / arbetad tid. Verifierad debiterbar tid per chaufför saknas; intäktskopplad TransPA-tid är en separat indikator.')),
 'recorded_revenue',round(recorded_revenue,2),'uninvoiced_revenue',round(recorded_revenue-coalesce(invoiced_revenue,0),2),
 'cost',round(cost,2),'estimated_payroll',round(estimated_payroll,2),'fuel',round(fuel,2),
 'fuel_share',round(fuel/nullif(invoiced_revenue,0)*100,2),'active_vehicle_count',active_vehicles,
 'coverage',jsonb_build_object('requested_months',p_months,'revenue_months',revenue_months,'cost_months',cost_months),
 'vehicles',coalesce((select jsonb_agg(to_jsonb(v) order by v.label) from vehicles v),'[]'::jsonb)) into output from totals cross join fleet;
 return output;
end $$;
revoke all on function private.hub_kpi_transport_period_report_v1(uuid,int,int[],jsonb) from public,anon,authenticated;

create or replace function public.hub_kpi_monthly_transport_report_v1(p_tenant_id uuid,p_fiscal_year int,p_month int,p_cost_center text default '30',p_filters jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare months int[]; scope jsonb; month_report jsonb; ytd_report jsonb; operations jsonb; generation uuid; report_date date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 perform private.hub_kpi_month_scope_v1(p_fiscal_year,array[p_month]);
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or exists(select 1 from jsonb_object_keys(p_filters) k where k not in ('group','unit','vehicle','project')) then raise exception 'Unsupported monthly report filter' using errcode='22023';end if;
 select array_agg(m order by ord) into months from unnest(array[9,10,11,12,1,2,3,4,5,6,7,8]) with ordinality a(m,ord) where ord<=case when p_month>=9 then p_month-8 else p_month+4 end;
 scope:=p_filters||case when nullif(trim(p_cost_center),'') is null then '{}'::jsonb else jsonb_build_object('cost_center',trim(p_cost_center)) end;
 generation:=private.hub_kpi_active_report_generation_v1(p_tenant_id);
 month_report:=private.hub_kpi_transport_period_report_v1(p_tenant_id,p_fiscal_year,array[p_month],scope);
 ytd_report:=case when cardinality(months)=1 then month_report else private.hub_kpi_transport_period_report_v1(p_tenant_id,p_fiscal_year,months,scope) end;
 operations:=private.hub_kpi_prepared_snapshot_v1(p_tenant_id,p_fiscal_year,array[p_month],scope);
 report_date:=make_date(case when p_month>=9 then p_fiscal_year else p_fiscal_year+1 end,p_month,1);
 return jsonb_build_object('version',1,'title','Nyckeltal Transport','tenant',(select name from public.hub_tenants where id=p_tenant_id),
 'period',jsonb_build_object('fiscal_year',p_fiscal_year,'month',p_month,'from',report_date,'to',(report_date+interval '1 month - 1 day')::date,'ytd_from',make_date(p_fiscal_year,9,1),'ytd_months',months),
 'scope',scope,'cost_centers',operations->'cost_centers','month',month_report,'ytd',ytd_report,
 'indicators',jsonb_build_object('reported_vehicle_utilization',operations#>'{transpa_vehicle_time,utilization}','reported_hours',operations#>'{transpa_vehicle_time,reported_hours}','available_hours',operations#>'{transpa_vehicle_time,available_hours}','definition','Rapporterad fordonstid från TransPA / beräknad vardagskapacitet. Detta är inte debiterbar tid.'),
 'generation',generation,'synced_at',(select completed_at from private.hub_kpi_report_generations where id=generation),
 'invoicing_rule','Alla registrerade intäkter räknas som fakturerade enligt användarens rapportregel 2026-10-06. Originalstatus ändras inte.','source_document','Nyckeltal Transport – 2026-10-02','generated_at',now());
end $$;
revoke all on function public.hub_kpi_monthly_transport_report_v1(uuid,int,int,text,jsonb) from public,anon;
grant execute on function public.hub_kpi_monthly_transport_report_v1(uuid,int,int,text,jsonb) to authenticated;
comment on function public.hub_kpi_monthly_transport_report_v1(uuid,int,int,text,jsonb) is 'Monthly delivery report: user-approved invoicing assumption, fiscal YTD, source coverage and explicit estimates. No synchronization or accounting writes.';
