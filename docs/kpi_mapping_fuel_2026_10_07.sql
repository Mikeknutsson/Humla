-- Applied 2026-10-07: exact Piusi reconciliation, default Workify vehicle routing and explainable matching queue.
CREATE OR REPLACE FUNCTION private.hub_kpi_monthly_fuel_sources_v1(p_tenant_id uuid, p_year integer, p_months integer[], p_filters jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 mapped as materialized(select f.*,c.center,c.business_group,u.unit_id,coalesce(u.unit_id::text,'vehicle:'||f.reg) unit_key,
 case when review_status='rejected' then null when review_status='approved' then corrected_cost_sek when liters>0 and raw_cost>0 and raw_cost/liters between 5 and 40 then raw_cost end accepted_cost,
 case when review_status='approved' then 'approved' when review_status='rejected' then 'excluded' when liters>0 and raw_cost>0 and raw_cost/liters between 5 and 40 then 'provisional' else 'manual_review' end price_status
 from raw f left join lateral(select case when count(distinct cost_center)=1 then max(cost_center) end center,
 case when count(distinct business_group)=1 then max(business_group) end business_group
 from private.hub_kpi_prepared_kpi_project_classification_periods c where c.generation_id=generation and c.tenant_id=p_tenant_id and f.reg=any(c.registrations) and c.valid_from<=f.dt and (c.valid_to is null or c.valid_to>=f.dt)) c on true left join lateral(select case when count(distinct u.unit_id)=1 then min(u.unit_id::text)::uuid end unit_id from private.hub_kpi_prepared_kpi_unit_periods u where u.generation_id=generation and u.tenant_id=p_tenant_id and u.valid_from<=f.dt and (u.valid_to is null or u.valid_to>=f.dt) and coalesce((u.payload->>'enabled')::boolean,false) and u.payload->'registrations'?f.reg) u on true),
 scoped as materialized(select * from mapped f where f.vehicle_id is not null
 and (not(p_filters?'cost_center') or f.center=any(string_to_array(p_filters->>'cost_center',',')))
 and (not(p_filters?'group') or f.business_group=any(string_to_array(p_filters->>'group',',')))
 and (not(p_filters?'vehicle') or f.reg=p_filters->>'vehicle')
 and (not(p_filters?'project') or exists(select 1 from private.hub_kpi_prepared_kpi_project_classification_periods c where c.generation_id=generation and c.tenant_id=p_tenant_id and c.project_reference=p_filters->>'project' and f.reg=any(c.registrations) and c.valid_from<=f.dt and (c.valid_to is null or c.valid_to>=f.dt)))
 and (not(p_filters?'unit') or p_filters->>'unit'='vehicle:'||f.reg or exists(select 1 from private.hub_kpi_prepared_kpi_unit_periods u where u.generation_id=generation and u.tenant_id=p_tenant_id and u.unit_id::text=p_filters->>'unit' and u.valid_from<=f.dt and (u.valid_to is null or u.valid_to>=f.dt) and coalesce((u.payload->>'enabled')::boolean,false) and u.payload->'registrations'?f.reg))),
 piusi_periods as(select distinct extract(month from dt)::int m from raw),
 next_fuel as materialized(select f.*,not(coalesce(description,'')='PS Olje AB' and extract(month from occurred_on)::int in(select m from piusi_periods)) include_cost from facts f where source='NEXT' and kind='cost' and category='fuel'),
 combined as(select 'Piusi' source,fact_id id,occurred_on dt,vehicle,amount,(original#>>'{_humla_fuel,quantity_liters}')::numeric liters,original#>>'{_humla_fuel,price_status}' price_status,original->>'product_name' product,coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') unit_key from facts where source='Piusi'
 union all select 'NEXT',fact_id,occurred_on,vehicle,amount,null,'imported',coalesce(original->>'Kontobeskrivning',description),coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') from next_fuel where include_cost),
 totals as(select count(*) rows,round(sum(amount),2) cost,round(sum(liters),2) liters,
 count(*) filter(where source='Piusi' and price_status='manual_review') review_rows,
 count(*) filter(where source='Piusi' and price_status='provisional') provisional_rows from combined)
 select jsonb_build_object('total_cost',case when rows>0 then cost end,'piusi_cost',(select round(sum(amount),2) from facts where source='Piusi'),'piusi_liters',(select round(sum((original#>>'{_humla_fuel,quantity_liters}')::numeric),2) from facts where source='Piusi'),
 'next_cost',(select round(sum(amount),2) from next_fuel where include_cost),'next_tank_purchase_excluded',(select round(coalesce(sum(coalesce((original#>>'{_humla_fuel_reconciliation,booked_amount}')::numeric,amount)),0),2) from next_fuel where not include_cost),
 'piusi_rows',(select count(*) from scoped),'review_rows',review_rows,'provisional_rows',provisional_rows,
 'unclassified_rows',(select count(*) from mapped where vehicle_id is null or center is null),
 'last_transaction_at',(select max(dt) from scoped),'source_state',(select to_jsonb(s)-'generation_id' from private.hub_kpi_prepared_fuel_state s where s.generation_id=generation),
 'basis','Piusi: godkända/rimlighetskontrollerade tankningsbelopp (preliminära). NEXT: övriga bränslekostnader. Endast exakt PS Olje AB egen tank undantas under månader med Piusi-underlag och visas som avstämning. Okopplade/ogiltiga tankningar hålls utanför beloppen.',
 'vehicles',coalesce((select jsonb_agg(x order by x.vehicle) from(select vehicle,round(sum(amount),2) fuel,round(sum(liters),2) liters from combined group by vehicle)x),'[]'::jsonb),
 'units',coalesce((select jsonb_agg(x) from(select unit_key,round(sum(amount),2) fuel,round(sum(liters),2) liters from combined group by unit_key)x),'[]'::jsonb),'transactions',coalesce((select jsonb_agg(to_jsonb(c) order by dt,id) from combined c),'[]'::jsonb)) into output from totals;
 return output;
end $function$;

CREATE OR REPLACE FUNCTION private.hub_kpi_prepare_piusi_facts_v1(p_tenant uuid, p_generation uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant) then raise exception 'Unknown generation';end if;
 if exists(select 1 from private.hub_kpi_prepared_facts where generation_id=p_generation and source='Piusi') then raise exception 'Fuel generation already prepared';end if;
 with raw as materialized(
 select o.id,o.data,(o.data->>'transaction_date')::timestamp::date dt,
 v.id vehicle_id,public.hub_normalize_vehicle_registration(coalesce(v.data->>'registration_number',o.data->>'registration_number')) reg,
 nullif(o.data->>'quantity_liters','')::numeric liters,nullif(o.data->>'source_amount','')::numeric raw_cost,
 r.status review_status,r.corrected_cost_sek
 from private.hub_kpi_prepared_hub_objects o
 left join private.hub_kpi_prepared_hub_objects v on v.generation_id=p_generation and v.tenant_id=p_tenant and v.object_type='Vehicle' and v.id::text=o.data->>'vehicle_id'
 left join private.hub_kpi_prepared_fuel_reviews r on r.generation_id=p_generation and r.tenant_id=p_tenant and r.hub_object_id=o.id
 where o.generation_id=p_generation and o.tenant_id=p_tenant and o.object_type='FuelTransaction' and o.data->>'source_system'='piusi_bsmart'),
 mapped as materialized(
 select f.*,c.center,c.center_name,c.business_group,c.project,
 case when review_status='rejected' then null when review_status='approved' then corrected_cost_sek when liters>0 and raw_cost>0 and raw_cost/liters between 5 and 40 then raw_cost end accepted_cost,
 case when review_status='approved' then 'approved' when review_status='rejected' then 'excluded' when liters>0 and raw_cost>0 and raw_cost/liters between 5 and 40 then 'provisional' else 'manual_review' end price_status,
 u.unit_id,u.unit_name,u.unit_group
 from raw f
 left join lateral(select case when count(distinct cost_center)=1 then max(cost_center) end center,
 case when count(distinct cost_center_name)=1 then max(cost_center_name) end center_name,
 case when count(distinct business_group)=1 then max(business_group) end business_group,
 case when count(distinct project_reference)=1 then max(project_reference) end project
 from private.hub_kpi_prepared_kpi_project_classification_periods c where c.generation_id=p_generation and c.tenant_id=p_tenant and f.reg=any(c.registrations) and c.valid_from<=f.dt and (c.valid_to is null or c.valid_to>=f.dt)) c on true
 left join lateral(select case when count(distinct up.unit_id)=1 then min(up.unit_id::text)::uuid end unit_id,
 case when count(distinct up.unit_id)=1 then max(up.payload->>'name') end unit_name,
 case when count(distinct up.unit_id)=1 then max(g.name) end unit_group
 from private.hub_kpi_prepared_kpi_unit_periods up
 left join private.hub_kpi_prepared_kpi_business_groups g on g.generation_id=p_generation and g.tenant_id=p_tenant and g.id::text=up.payload->>'business_group_id'
 where up.generation_id=p_generation and up.tenant_id=p_tenant and up.valid_from<=f.dt and (up.valid_to is null or up.valid_to>=f.dt)
 and coalesce((up.payload->>'enabled')::boolean,false) and up.payload->'registrations'?f.reg) u on true)
 insert into private.hub_kpi_prepared_facts(generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,description,account,file_name,row_number,original,cost_center,cost_center_name,classification_source,display_original)
 select p_generation,p_tenant,extract(year from dt)::int-case when extract(month from dt)<9 then 1 else 0 end,
 'piusi:'||f.id,dt,'cost',accepted_cost,'fuel',project,reg,unit_id,unit_name,coalesce(unit_group,business_group,'Ej klassificerat'),'Piusi',
 'Tankning '||coalesce(data->>'product_name','drivmedel'),null,'Piusi API',null,
 data||jsonb_build_object('_humla_fuel',jsonb_build_object('price_status',price_status,'quantity_liters',liters,'accepted_cost_sek',accepted_cost,'hub_object_id',f.id)),
 coalesce(center,'unclassified'),coalesce(center_name,'Ej klassificerat'),jsonb_build_object('source','prepared_hub_vehicle_and_unit_periods'),
 jsonb_build_object('_humla_fuel',jsonb_build_object('price_status',price_status,'quantity_liters',liters))
 from mapped f join private.hub_kpi_report_generations gen on gen.id=p_generation
 where vehicle_id is not null and accepted_cost is not null
 and dt between make_date(gen.first_fiscal_year,9,1) and make_date(gen.last_fiscal_year+1,8,31);
 update private.hub_kpi_prepared_facts f
 set original=f.original||jsonb_build_object('_humla_fuel_reconciliation',jsonb_build_object('booked_amount',f.amount,'reason','Egen tank: endast exakt PS Olje AB; Piusi consumption is the cost basis for this month')),
 display_original=f.display_original||jsonb_build_object('_humla_fuel_reconciliation',jsonb_build_object('booked_amount',f.amount)),amount=0
 where f.generation_id=p_generation and f.source='NEXT' and f.kind='cost' and f.category='fuel' and f.description='PS Olje AB'
 and exists(select 1 from private.hub_kpi_prepared_hub_objects o where o.generation_id=p_generation and o.tenant_id=p_tenant and o.object_type='FuelTransaction' and o.data->>'source_system'='piusi_bsmart'
 and date_trunc('month',(o.data->>'transaction_date')::timestamp)::date=date_trunc('month',f.occurred_on)::date);
end $function$;

CREATE OR REPLACE FUNCTION private.hub_kpi_financial_facts_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 then raise exception 'Invalid period'; end if;
 return query
 with allocation_rules as materialized(select * from public.kpi_dashboard_allocations where tenant_id=p_tenant_id and valid_from<=p_to and (valid_to is null or valid_to>=p_from)), unit_versions as materialized (
  select (jsonb_populate_record(null::public.kpi_units,to_jsonb(u)||v.payload||jsonb_build_object('valid_from',v.valid_from,'valid_to',v.valid_to))).*
  from public.kpi_units u join public.kpi_unit_periods v on v.unit_id=u.id and v.tenant_id=u.tenant_id
  where u.tenant_id=p_tenant_id and u.origin in ('manual','manual_builder') and v.valid_from<=p_to and (v.valid_to is null or v.valid_to>=p_from)
  union all select u.* from public.kpi_units u where u.tenant_id=p_tenant_id and u.origin in ('manual','manual_builder')
   and not exists(select 1 from public.kpi_unit_periods v where v.unit_id=u.id)
   and u.valid_from<=p_to and (u.valid_to is null or u.valid_to>=p_from)
 ), unit_group_versions as materialized (
  select p.unit_id,p.valid_from,p.valid_to,g.name
  from public.kpi_unit_periods p join public.kpi_business_groups g
   on g.id::text=p.payload->>'business_group_id' and g.tenant_id=p.tenant_id and g.enabled
  where p.tenant_id=p_tenant_id and p.valid_from<=p_to and (p.valid_to is null or p.valid_to>=p_from)
 ), cfg0 as (
  select coalesce(monthly_salary,34000)::numeric salary,coalesce(weekly_hours,40)::numeric wh,coalesce(overtime_multiplier,1.5)::numeric ot,
   (1+(coalesce(employer_contribution_pct,31.42)+coalesce(pension_pct,4.5)+coalesce(other_overhead_pct,0))/100)::numeric load
  from public.kpi_personnel_salary_settings where tenant_id=p_tenant_id and is_default limit 1
 ), cfg as (select * from cfg0 union all select 34000,40,1.5,1.3592 where not exists(select 1 from cfg0)),
 times as (select t.*,date_trunc('week',work_date)::date wk from public.kpi_transpa_time_facts t where t.tenant_id=p_tenant_id and work_date between p_from and p_to and work_hours>0),
 weeks as (select employee_id,wk,sum(work_hours) hours from times group by 1,2),
 payroll as (
  select t.*,(case when w.hours<=c.wh then t.work_hours else t.work_hours*c.wh/w.hours end +
   case when w.hours<=c.wh then 0 else t.work_hours*(w.hours-c.wh)/w.hours*c.ot end)*c.salary/(c.wh*52/12)*c.load pc
  from times t join weeks w using(employee_id,wk) cross join cfg c
 ), imports as (
  select x.id::text fid,x.occurred_on dt,x.data_kind k,x.amount amt,
   case when x.data_kind='revenue' then coalesce(ar.revenue_category,'unclassified')
    when x.project_reference='9009' and cr.cost_category='material' then 'material' when x.project_reference='9009' then 'hired' when x.project_reference='5100' then 'tipp_deponi'
    when x.account in ('5360','5621','5631') then 'fuel' else coalesce(cr.cost_category,'other') end cat,
   case when x.data_kind='revenue' then case when nullif(x.allocation->>'project_carrier_reference','') is not null then x.allocation->>'project_carrier_reference' when ov.order_name is not null then null when ar.target_type='project' then private.hub_kpi_project_reference_v1(p_tenant_id,ar.project_reference) else null end
    else coalesce(nullif(x.allocation->>'allocation_reference',''),x.project_reference) end proj,
   case when x.data_kind='revenue' and nullif(x.allocation->>'project_carrier_reference','') is null and (ov.order_name is not null or coalesce(ar.target_type,'vehicle')='vehicle') then case when ov.order_name is not null then case when upper(trim(x.vehicle_registration)) ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then upper(trim(x.vehicle_registration)) end else upper(trim(x.vehicle_registration)) end
    when x.data_kind='cost' then null else null end reg,
   case when x.data_kind='cost' then 'NEXT' else 'Workify' end src,x.description descr,x.account acc,b.file_name fn,x.row_number rn,case when x.data_kind='cost' then x.source_data||jsonb_build_object('_humla_include_in_vehicle_result',cr.include_in_vehicle_result) else x.source_data end || case when ov.order_name is not null then jsonb_build_object('_humla_order_vehicle_rule',ov.order_name,'_humla_order_vehicle_status',case when nullif(trim(x.vehicle_registration),'') is null then 'missing_vehicle' when upper(trim(x.vehicle_registration)) ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then 'matched' else 'invalid_vehicle' end) else '{}'::jsonb end || jsonb_build_object('_humla_project_fallback',x.allocation->'project_carrier_fallback') || jsonb_build_object('_humla_cost_center',coalesce(nullif(x.cost_center,''),nullif(b.provenance->>'cost_center',''))) raw
  from public.kpi_import_rows x join public.kpi_import_batches b on b.id=x.batch_id
  left join lateral (select a.* from public.kpi_workify_article_rules a where a.tenant_id=p_tenant_id and a.enabled and a.article_number=coalesce(x.source_data->>'Artikelnummer','') and x.occurred_on>=a.valid_from and (a.valid_to is null or x.occurred_on<=a.valid_to) order by a.valid_from desc,a.id limit 1) ar on true
  left join lateral (
   select r.order_name from private.hub_kpi_workify_order_vehicle_rules r
   where x.data_kind='revenue' and r.tenant_id=p_tenant_id and r.enabled
    and r.valid_from<=x.occurred_on and (r.valid_to is null or r.valid_to>=x.occurred_on)
    and r.order_name=lower(regexp_replace(trim(coalesce(nullif(x.project_reference,''),x.source_data->>'Littranummer','')),'\s+',' ','g'))
   order by r.valid_from desc limit 1
  ) ov on true
  left join lateral (select r.cost_category,r.include_in_vehicle_result from public.kpi_cost_category_rules r where r.tenant_id=p_tenant_id and r.account=x.account and x.occurred_on>=r.valid_from and (r.valid_to is null or x.occurred_on<=r.valid_to) order by r.valid_from desc,r.id limit 1) cr on true
  where x.tenant_id=p_tenant_id and (x.data_kind<>'revenue' or x.amount<>0) and x.is_valid and coalesce(ar.revenue_category,'')<>'ignored' and x.data_kind in ('revenue','cost') and x.occurred_on between p_from and p_to
 ), raw_facts as (
  select * from imports
  union all
  select 'transpa:'||t.time_report_id||':'||coalesce(j.ordinality,0),t.work_date,'cost',t.pc/greatest(jsonb_array_length(coalesce(t.transpa_vehicle_ids,'[]')),1),
   'personnel',null,upper(trim(v.payload->>'registrationNumber')),'TransPA',
   'Beräknad personalkostnad från TransPA-tid (Hub-schablon)',null,null,null,
   jsonb_build_object('time_report_id',t.time_report_id,'employee_id',t.employee_id,'work_date',t.work_date,'work_hours',t.work_hours,'report_status',t.report_status,'calculation','hub_kpi_personnel_costs_engine_v1','actual_payroll',false)
  from payroll t left join lateral jsonb_array_elements(t.transpa_vehicle_ids) with ordinality j(value,ordinality) on true
  left join public.hub_transpa_entities v on v.tenant_id=p_tenant_id and v.entity_type='vehicle' and v.external_id=j.value#>>'{}'
  union all
  select 'depreciation:'||d.id||':'||gs::date,greatest(gs::date,p_from,d.valid_from),'cost',d.monthly_depreciation,'depreciation',null,upper(trim(d.object_reference)),'Avskrivningsregister',
   'Månadsavskrivning',null,null,null,jsonb_build_object('register_id',d.id,'valid_from',d.valid_from,'valid_to',d.valid_to,'monthly_depreciation',d.monthly_depreciation)
  from public.kpi_asset_depreciation_periods d cross join lateral generate_series(date_trunc('month',greatest(p_from,d.valid_from)),date_trunc('month',least(p_to,coalesce(d.valid_to,p_to))),interval '1 month') gs
  where d.tenant_id=p_tenant_id and d.valid_from<=p_to and (d.valid_to is null or d.valid_to>=p_from)
 ), routed as (
  select f.fid,f.dt,f.k,f.amt,f.cat,coalesce(a.target,f.proj) proj,coalesce(v.target,f.reg) reg,f.src,f.descr,f.acc,f.fn,f.rn,
   f.raw||case when a.target is not null then jsonb_build_object('_humla_original_project',f.proj,'_humla_project_assignment',a.target) else '{}'::jsonb end||case when v.target is not null then jsonb_build_object('_humla_original_registration',f.reg,'_humla_vehicle_assignment',v.target) else '{}'::jsonb end raw
  from raw_facts f left join lateral(
   select r.target from allocation_rules r
   where r.dimension='project' and r.source=f.src and r.kind=f.k and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt)
   and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=f.proj when 'vehicle' then r.reference=coalesce(nullif(f.reg,''),(select case when count(distinct upper(trim(pm.vehicle_registration)))=1 then max(upper(trim(pm.vehicle_registration))) end from (select project_reference,vehicle_registration,valid_from,valid_to,true enabled,tenant_id from public.kpi_project_vehicle_periods where tenant_id=p_tenant_id union all select project_reference,vehicle_registration,valid_from,valid_to,enabled,tenant_id from public.kpi_project_unit_mappings legacy where tenant_id=p_tenant_id and not exists(select 1 from public.kpi_project_vehicle_periods h where h.tenant_id=p_tenant_id and h.project_reference=legacy.project_reference)) pm where pm.enabled and pm.project_reference=f.proj and f.dt>=coalesce(pm.valid_from,'2000-01-01') and (pm.valid_to is null or f.dt<=pm.valid_to))) when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc else false end
   order by case r.reference_type when 'fact' then 1 when 'project' then 2 when 'vehicle' then 3 when 'article' then 4 else 5 end,r.valid_from desc,r.created_at desc limit 1
  ) a on true
  left join lateral(
   select r.target from allocation_rules r
   where r.dimension='vehicle' and r.source=f.src and r.kind=f.k and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt)
   and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=f.proj when 'vehicle' then r.reference=f.reg when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc else false end
   order by case r.reference_type when 'fact' then 1 when 'project' then 2 when 'vehicle' then 3 when 'article' then 4 else 5 end,r.valid_from desc,r.created_at desc limit 1
  ) v on true
 ), mapped as (
  select f.*,case when f.raw->>'_humla_project_fallback'='true' then null when f.k='cost' and f.raw->>'_humla_include_in_vehicle_result'='false' then null when f.proj='9009' or f.reg='LASTBIL' then 'LASTBIL' else coalesce(nullif(f.reg,''),m.reg) end vrn
  from routed f left join lateral (
   select case when count(distinct upper(trim(vehicle_registration)))=1 then max(upper(trim(vehicle_registration))) end reg
   from (select project_reference,vehicle_registration,valid_from,valid_to,true enabled,tenant_id from public.kpi_project_vehicle_periods where tenant_id=p_tenant_id union all select project_reference,vehicle_registration,valid_from,valid_to,enabled,tenant_id from public.kpi_project_unit_mappings legacy where tenant_id=p_tenant_id and not exists(select 1 from public.kpi_project_vehicle_periods h where h.tenant_id=p_tenant_id and h.project_reference=legacy.project_reference)) pm where pm.tenant_id=p_tenant_id and pm.enabled and pm.project_reference=f.proj and f.dt>=coalesce(pm.valid_from,'2000-01-01') and (pm.valid_to is null or f.dt<=pm.valid_to)
  ) m on true
 ), related as (
  select f.*,u.uid,u.uname,u.match_count unit_match_count,ug.match_count unit_group_match_count,
   case when u.match_count>1 or ug.match_count>1 then 'Ej klassificerat' else coalesce(ug.name,case when f.proj='9009' or f.vrn='LASTBIL' then 'Inhyrda' else coalesce(bg.name,'Ej klassificerat') end) end grp
  from mapped f left join lateral (
   select case when count(distinct un.id)=1 then (array_agg(distinct un.id))[1] end uid,
    case when count(distinct un.id)=1 then max(un.name) end uname,count(distinct un.id) match_count
   from unit_versions un where un.tenant_id=p_tenant_id and un.enabled and un.origin in ('manual','manual_builder') and un.valid_from<=f.dt and (un.valid_to is null or un.valid_to>=f.dt)
   and (f.k<>'cost' or coalesce((f.raw->>'_humla_include_in_vehicle_result')::boolean,true) or un.unit_type='overhead') and (f.proj=any(un.projects) or f.vrn=any(un.registrations) or f.raw->>'employee_id'=any(un.employees) or exists(
    select 1 from public.kpi_unit_components c where c.tenant_id=p_tenant_id and c.unit_id=un.id and c.component_type in ('vehicle','trailer','other') and upper(trim(c.component_reference))=f.vrn and coalesce(c.valid_from,un.valid_from)<=f.dt and (c.valid_to is null or f.dt<=c.valid_to)))
  ) u on true
  left join lateral (
   select count(distinct g.name) match_count,case when count(distinct g.name)=1 then max(g.name) end name
   from unit_group_versions g where g.unit_id=u.uid and g.valid_from<=f.dt and (g.valid_to is null or g.valid_to>=f.dt)
  ) ug on true
  left join lateral (
   select case when count(distinct p.business_group_id)=1 then (array_agg(distinct p.business_group_id))[1] end gid
   from public.kpi_project_business_groups p where p.tenant_id=p_tenant_id and p.project_reference=f.proj and f.dt>=coalesce(p.valid_from,'2000-01-01') and (p.valid_to is null or f.dt<=p.valid_to)
  ) pg on true left join public.kpi_business_groups bg on bg.id=pg.gid and bg.tenant_id=p_tenant_id and bg.enabled
 ), decorated as(select f.fid,f.dt,f.k,f.amt,coalesce(a.targets->>'category',f.cat) cat,f.proj,coalesce(a.targets->>'vehicle',f.vrn) vrn,coalesce(assigned.id,f.uid) uid,coalesce(assigned.name,f.uname) uname,
coalesce(a.targets->>'group',assigned.grp,f.grp) grp,f.src,f.descr,f.acc,f.fn,f.rn,f.raw||jsonb_build_object('_humla_assignment',a.targets,'_humla_identity_resolution',jsonb_build_object('unit_matches',f.unit_match_count,'group_matches',f.unit_group_match_count)) raw
from related f left join lateral(
 select jsonb_object_agg(dimension,target) targets from(
 select distinct on (dimension) dimension,target from allocation_rules r where r.source=f.src and r.kind=f.k and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt)
 and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=case when f.raw?'_humla_original_project' then f.raw->>'_humla_original_project' else f.proj end when 'vehicle' then (r.reference=f.vrn or r.reference=f.raw->>'_humla_original_registration') when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc else false end
 order by dimension,case r.reference_type when 'fact' then 1 when 'project' then 2 when 'vehicle' then 3 when 'article' then 4 else 5 end,r.valid_from desc,r.created_at desc
 ) matching
) a on true left join lateral(
 select u.id,u.name,(select g.name from unit_group_versions g where g.unit_id=u.id and g.valid_from<=f.dt and (g.valid_to is null or g.valid_to>=f.dt) limit 1) grp from unit_versions u
 where u.id::text=a.targets->>'unit' and u.enabled and u.valid_from<=f.dt and (u.valid_to is null or u.valid_to>=f.dt) limit 1
) assigned on true
)
 select case when recipients.id is null then f.fid else f.fid||':share:'||recipients.id::text end,f.dt,f.k,
 case when recipients.id is null then f.amt when recipients.position=recipients.n then f.amt-round(f.amt/recipients.n,2)*(recipients.n-1) else round(f.amt/recipients.n,2) end,
 f.cat,f.proj,case when recipients.id is not null then case when recipients.name ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then recipients.name end when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then null else f.vrn end,
 case when recipients.id is not null then recipients.id when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then null else f.uid end,
 case when recipients.id is not null then recipients.name when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then null else f.uname end,
 case when recipients.id is not null then coalesce(recipients.grp,'Ej klassificerat') when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then 'Ej klassificerat' else f.grp end,
 f.src,f.descr,f.acc,f.fn,f.rn,
 f.raw||case when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then jsonb_build_object('_humla_distribution',jsonb_build_object('method','equal','scope',f.raw#>>'{_humla_assignment,shared_cost}','original_fact_id',f.fid,'original_amount',f.amt,'recipient_count',coalesce(recipients.n,0),'recipient_unit',recipients.id,'status',case when recipients.id is null then 'no_eligible_units' else 'allocated' end)) else '{}'::jsonb end
 from decorated f left join lateral(
 select eligible.*,count(*)over() n,row_number()over(order by eligible.id) position
 from (
  select distinct on(u.id) u.id,u.name,coalesce(own.name,registry.name) grp from unit_versions u
  left join lateral(select name from unit_group_versions g where g.unit_id=u.id and g.valid_from<=f.dt and (g.valid_to is null or g.valid_to>=f.dt) order by g.valid_from desc limit 1)own on true
  left join lateral(
   select case when count(distinct r.business_group)=1 then min(r.business_group) end name from public.kpi_project_classification_periods r
   where r.tenant_id=p_tenant_id and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt) and u.name=any(r.registrations) and r.business_group is not null
  )registry on own.name is null
  where f.k='cost' and f.src='NEXT' and f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','')
  and u.enabled and u.valid_from<=f.dt and (u.valid_to is null or u.valid_to>=f.dt)
  and (f.raw#>>'{_humla_assignment,shared_cost}'='*' or case when left(f.raw#>>'{_humla_assignment,shared_cost}',1)='[' then u.id::text in(select value from jsonb_array_elements_text((f.raw#>>'{_humla_assignment,shared_cost}')::jsonb)) else coalesce(own.name,registry.name)=f.raw#>>'{_humla_assignment,shared_cost}' end)
  order by u.id,u.valid_from desc
 )eligible
 )recipients on true;
end $function$;

CREATE OR REPLACE FUNCTION private.hub_kpi_financial_month_facts_v1(p_tenant_id uuid, p_from date, p_to date, p_months integer[])
 RETURNS TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 then raise exception 'Invalid period'; end if;
 return query
 with allocation_rules as materialized(select * from public.kpi_dashboard_allocations where tenant_id=p_tenant_id and valid_from<=p_to and (valid_to is null or valid_to>=p_from)), unit_versions as materialized (
  select (jsonb_populate_record(null::public.kpi_units,to_jsonb(u)||v.payload||jsonb_build_object('valid_from',v.valid_from,'valid_to',v.valid_to))).*
  from public.kpi_units u join public.kpi_unit_periods v on v.unit_id=u.id and v.tenant_id=u.tenant_id
  where u.tenant_id=p_tenant_id and u.origin in ('manual','manual_builder') and v.valid_from<=p_to and (v.valid_to is null or v.valid_to>=p_from)
  union all select u.* from public.kpi_units u where u.tenant_id=p_tenant_id and u.origin in ('manual','manual_builder')
   and not exists(select 1 from public.kpi_unit_periods v where v.unit_id=u.id)
   and u.valid_from<=p_to and (u.valid_to is null or u.valid_to>=p_from)
 ), unit_group_versions as materialized (
  select p.unit_id,p.valid_from,p.valid_to,g.name
  from public.kpi_unit_periods p join public.kpi_business_groups g
   on g.id::text=p.payload->>'business_group_id' and g.tenant_id=p.tenant_id and g.enabled
  where p.tenant_id=p_tenant_id and p.valid_from<=p_to and (p.valid_to is null or p.valid_to>=p_from)
 ), cfg0 as (
  select coalesce(monthly_salary,34000)::numeric salary,coalesce(weekly_hours,40)::numeric wh,coalesce(overtime_multiplier,1.5)::numeric ot,
   (1+(coalesce(employer_contribution_pct,31.42)+coalesce(pension_pct,4.5)+coalesce(other_overhead_pct,0))/100)::numeric load
  from public.kpi_personnel_salary_settings where tenant_id=p_tenant_id and is_default limit 1
 ), cfg as (select * from cfg0 union all select 34000,40,1.5,1.3592 where not exists(select 1 from cfg0)),
 times as (select t.*,date_trunc('week',work_date)::date wk from public.kpi_transpa_time_facts t where t.tenant_id=p_tenant_id and work_date between p_from and p_to and work_hours>0),
 weeks as (select employee_id,wk,sum(work_hours) hours from times group by 1,2),
 payroll as (
  select t.*,(case when w.hours<=c.wh then t.work_hours else t.work_hours*c.wh/w.hours end +
   case when w.hours<=c.wh then 0 else t.work_hours*(w.hours-c.wh)/w.hours*c.ot end)*c.salary/(c.wh*52/12)*c.load pc
  from times t join weeks w using(employee_id,wk) cross join cfg c
 ), imports as (
  select x.id::text fid,x.occurred_on dt,x.data_kind k,x.amount amt,
   case when x.data_kind='revenue' then coalesce(ar.revenue_category,'unclassified')
    when x.project_reference='9009' and cr.cost_category='material' then 'material' when x.project_reference='9009' then 'hired' when x.project_reference='5100' then 'tipp_deponi'
    when x.account in ('5360','5621','5631') then 'fuel' else coalesce(cr.cost_category,'other') end cat,
   case when x.data_kind='revenue' then case when nullif(x.allocation->>'project_carrier_reference','') is not null then x.allocation->>'project_carrier_reference' when ov.order_name is not null then null when ar.target_type='project' then private.hub_kpi_project_reference_v1(p_tenant_id,ar.project_reference) else null end
    else coalesce(nullif(x.allocation->>'allocation_reference',''),x.project_reference) end proj,
   case when x.data_kind='revenue' and nullif(x.allocation->>'project_carrier_reference','') is null and (ov.order_name is not null or coalesce(ar.target_type,'vehicle')='vehicle') then case when ov.order_name is not null then case when upper(trim(x.vehicle_registration)) ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then upper(trim(x.vehicle_registration)) end else upper(trim(x.vehicle_registration)) end
    when x.data_kind='cost' then null else null end reg,
   case when x.data_kind='cost' then 'NEXT' else 'Workify' end src,x.description descr,x.account acc,b.file_name fn,x.row_number rn,case when x.data_kind='cost' then x.source_data||jsonb_build_object('_humla_include_in_vehicle_result',cr.include_in_vehicle_result) else x.source_data end || case when ov.order_name is not null then jsonb_build_object('_humla_order_vehicle_rule',ov.order_name,'_humla_order_vehicle_status',case when nullif(trim(x.vehicle_registration),'') is null then 'missing_vehicle' when upper(trim(x.vehicle_registration)) ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then 'matched' else 'invalid_vehicle' end) else '{}'::jsonb end || jsonb_build_object('_humla_project_fallback',x.allocation->'project_carrier_fallback') || jsonb_build_object('_humla_cost_center',coalesce(nullif(x.cost_center,''),nullif(b.provenance->>'cost_center',''))) raw
  from public.kpi_import_rows x join public.kpi_import_batches b on b.id=x.batch_id
  left join lateral (select a.* from public.kpi_workify_article_rules a where a.tenant_id=p_tenant_id and a.enabled and a.article_number=coalesce(x.source_data->>'Artikelnummer','') and x.occurred_on>=a.valid_from and (a.valid_to is null or x.occurred_on<=a.valid_to) order by a.valid_from desc,a.id limit 1) ar on true
  left join lateral (
   select r.order_name from private.hub_kpi_workify_order_vehicle_rules r
   where x.data_kind='revenue' and r.tenant_id=p_tenant_id and r.enabled
    and r.valid_from<=x.occurred_on and (r.valid_to is null or r.valid_to>=x.occurred_on)
    and r.order_name=lower(regexp_replace(trim(coalesce(nullif(x.project_reference,''),x.source_data->>'Littranummer','')),'\s+',' ','g'))
   order by r.valid_from desc limit 1
  ) ov on true
  left join lateral (select r.cost_category,r.include_in_vehicle_result from public.kpi_cost_category_rules r where r.tenant_id=p_tenant_id and r.account=x.account and x.occurred_on>=r.valid_from and (r.valid_to is null or x.occurred_on<=r.valid_to) order by r.valid_from desc,r.id limit 1) cr on true
  where x.tenant_id=p_tenant_id and (x.data_kind<>'revenue' or x.amount<>0) and x.is_valid and coalesce(ar.revenue_category,'')<>'ignored' and x.data_kind in ('revenue','cost') and x.occurred_on between p_from and p_to and (p_months is null or extract(month from x.occurred_on)::int=any(p_months))
 ), raw_facts as (
  select * from imports
  union all
  select 'transpa:'||t.time_report_id||':'||coalesce(j.ordinality,0),t.work_date,'cost',t.pc/greatest(jsonb_array_length(coalesce(t.transpa_vehicle_ids,'[]')),1),
   'personnel',null,upper(trim(v.payload->>'registrationNumber')),'TransPA',
   'Beräknad personalkostnad från TransPA-tid (Hub-schablon)',null,null,null,
   jsonb_build_object('time_report_id',t.time_report_id,'employee_id',t.employee_id,'work_date',t.work_date,'work_hours',t.work_hours,'report_status',t.report_status,'calculation','hub_kpi_personnel_costs_engine_v1','actual_payroll',false)
  from payroll t left join lateral jsonb_array_elements(t.transpa_vehicle_ids) with ordinality j(value,ordinality) on true
  left join public.hub_transpa_entities v on v.tenant_id=p_tenant_id and v.entity_type='vehicle' and v.external_id=j.value#>>'{}'
  where p_months is null or extract(month from t.work_date)::int=any(p_months)
  union all
  select 'depreciation:'||d.id||':'||gs::date,greatest(gs::date,p_from,d.valid_from),'cost',d.monthly_depreciation,'depreciation',null,upper(trim(d.object_reference)),'Avskrivningsregister',
   'Månadsavskrivning',null,null,null,jsonb_build_object('register_id',d.id,'valid_from',d.valid_from,'valid_to',d.valid_to,'monthly_depreciation',d.monthly_depreciation)
  from public.kpi_asset_depreciation_periods d cross join lateral generate_series(date_trunc('month',greatest(p_from,d.valid_from)),date_trunc('month',least(p_to,coalesce(d.valid_to,p_to))),interval '1 month') gs
  where d.tenant_id=p_tenant_id and d.valid_from<=p_to and (d.valid_to is null or d.valid_to>=p_from) and (p_months is null or extract(month from greatest(gs::date,p_from,d.valid_from))::int=any(p_months))
 ), routed as (
  select f.fid,f.dt,f.k,f.amt,f.cat,coalesce(a.target,f.proj) proj,coalesce(v.target,f.reg) reg,f.src,f.descr,f.acc,f.fn,f.rn,
   f.raw||case when a.target is not null then jsonb_build_object('_humla_original_project',f.proj,'_humla_project_assignment',a.target) else '{}'::jsonb end||case when v.target is not null then jsonb_build_object('_humla_original_registration',f.reg,'_humla_vehicle_assignment',v.target) else '{}'::jsonb end raw
  from raw_facts f left join lateral(
   select r.target from allocation_rules r
   where r.dimension='project' and r.source=f.src and r.kind=f.k and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt)
   and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=f.proj when 'vehicle' then r.reference=coalesce(nullif(f.reg,''),(select case when count(distinct upper(trim(pm.vehicle_registration)))=1 then max(upper(trim(pm.vehicle_registration))) end from (select project_reference,vehicle_registration,valid_from,valid_to,true enabled,tenant_id from public.kpi_project_vehicle_periods where tenant_id=p_tenant_id union all select project_reference,vehicle_registration,valid_from,valid_to,enabled,tenant_id from public.kpi_project_unit_mappings legacy where tenant_id=p_tenant_id and not exists(select 1 from public.kpi_project_vehicle_periods h where h.tenant_id=p_tenant_id and h.project_reference=legacy.project_reference)) pm where pm.enabled and pm.project_reference=f.proj and f.dt>=coalesce(pm.valid_from,'2000-01-01') and (pm.valid_to is null or f.dt<=pm.valid_to))) when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc else false end
   order by case r.reference_type when 'fact' then 1 when 'project' then 2 when 'vehicle' then 3 when 'article' then 4 else 5 end,r.valid_from desc,r.created_at desc limit 1
  ) a on true
  left join lateral(
   select r.target from allocation_rules r
   where r.dimension='vehicle' and r.source=f.src and r.kind=f.k and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt)
   and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=f.proj when 'vehicle' then r.reference=f.reg when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc else false end
   order by case r.reference_type when 'fact' then 1 when 'project' then 2 when 'vehicle' then 3 when 'article' then 4 else 5 end,r.valid_from desc,r.created_at desc limit 1
  ) v on true
 ), mapped as (
  select f.*,case when f.raw->>'_humla_project_fallback'='true' then null when f.k='cost' and f.raw->>'_humla_include_in_vehicle_result'='false' then null when f.proj='9009' or f.reg='LASTBIL' then 'LASTBIL' else coalesce(nullif(f.reg,''),m.reg) end vrn
  from routed f left join lateral (
   select case when count(distinct upper(trim(vehicle_registration)))=1 then max(upper(trim(vehicle_registration))) end reg
   from (select project_reference,vehicle_registration,valid_from,valid_to,true enabled,tenant_id from public.kpi_project_vehicle_periods where tenant_id=p_tenant_id union all select project_reference,vehicle_registration,valid_from,valid_to,enabled,tenant_id from public.kpi_project_unit_mappings legacy where tenant_id=p_tenant_id and not exists(select 1 from public.kpi_project_vehicle_periods h where h.tenant_id=p_tenant_id and h.project_reference=legacy.project_reference)) pm where pm.tenant_id=p_tenant_id and pm.enabled and pm.project_reference=f.proj and f.dt>=coalesce(pm.valid_from,'2000-01-01') and (pm.valid_to is null or f.dt<=pm.valid_to)
  ) m on true
 ), related as (
  select f.*,u.uid,u.uname,u.match_count unit_match_count,ug.match_count unit_group_match_count,
   case when u.match_count>1 or ug.match_count>1 then 'Ej klassificerat' else coalesce(ug.name,case when f.proj='9009' or f.vrn='LASTBIL' then 'Inhyrda' else coalesce(bg.name,'Ej klassificerat') end) end grp
  from mapped f left join lateral (
   select case when count(distinct un.id)=1 then (array_agg(distinct un.id))[1] end uid,
    case when count(distinct un.id)=1 then max(un.name) end uname,count(distinct un.id) match_count
   from unit_versions un where un.tenant_id=p_tenant_id and un.enabled and un.origin in ('manual','manual_builder') and un.valid_from<=f.dt and (un.valid_to is null or un.valid_to>=f.dt)
   and (f.k<>'cost' or coalesce((f.raw->>'_humla_include_in_vehicle_result')::boolean,true) or un.unit_type='overhead') and (f.proj=any(un.projects) or f.vrn=any(un.registrations) or f.raw->>'employee_id'=any(un.employees) or exists(
    select 1 from public.kpi_unit_components c where c.tenant_id=p_tenant_id and c.unit_id=un.id and c.component_type in ('vehicle','trailer','other') and upper(trim(c.component_reference))=f.vrn and coalesce(c.valid_from,un.valid_from)<=f.dt and (c.valid_to is null or f.dt<=c.valid_to)))
  ) u on true
  left join lateral (
   select count(distinct g.name) match_count,case when count(distinct g.name)=1 then max(g.name) end name
   from unit_group_versions g where g.unit_id=u.uid and g.valid_from<=f.dt and (g.valid_to is null or g.valid_to>=f.dt)
  ) ug on true
  left join lateral (
   select case when count(distinct p.business_group_id)=1 then (array_agg(distinct p.business_group_id))[1] end gid
   from public.kpi_project_business_groups p where p.tenant_id=p_tenant_id and p.project_reference=f.proj and f.dt>=coalesce(p.valid_from,'2000-01-01') and (p.valid_to is null or f.dt<=p.valid_to)
  ) pg on true left join public.kpi_business_groups bg on bg.id=pg.gid and bg.tenant_id=p_tenant_id and bg.enabled
 ), decorated as(select f.fid,f.dt,f.k,f.amt,coalesce(a.targets->>'category',f.cat) cat,f.proj,coalesce(a.targets->>'vehicle',f.vrn) vrn,coalesce(assigned.id,f.uid) uid,coalesce(assigned.name,f.uname) uname,
coalesce(a.targets->>'group',assigned.grp,f.grp) grp,f.src,f.descr,f.acc,f.fn,f.rn,f.raw||jsonb_build_object('_humla_assignment',a.targets,'_humla_identity_resolution',jsonb_build_object('unit_matches',f.unit_match_count,'group_matches',f.unit_group_match_count)) raw
from related f left join lateral(
 select jsonb_object_agg(dimension,target) targets from(
 select distinct on (dimension) dimension,target from allocation_rules r where r.source=f.src and r.kind=f.k and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt)
 and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=case when f.raw?'_humla_original_project' then f.raw->>'_humla_original_project' else f.proj end when 'vehicle' then (r.reference=f.vrn or r.reference=f.raw->>'_humla_original_registration') when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc else false end
 order by dimension,case r.reference_type when 'fact' then 1 when 'project' then 2 when 'vehicle' then 3 when 'article' then 4 else 5 end,r.valid_from desc,r.created_at desc
 ) matching
) a on true left join lateral(
 select u.id,u.name,(select g.name from unit_group_versions g where g.unit_id=u.id and g.valid_from<=f.dt and (g.valid_to is null or g.valid_to>=f.dt) limit 1) grp from unit_versions u
 where u.id::text=a.targets->>'unit' and u.enabled and u.valid_from<=f.dt and (u.valid_to is null or u.valid_to>=f.dt) limit 1
) assigned on true
)
 select case when recipients.id is null then f.fid else f.fid||':share:'||recipients.id::text end,f.dt,f.k,
 case when recipients.id is null then f.amt when recipients.position=recipients.n then f.amt-round(f.amt/recipients.n,2)*(recipients.n-1) else round(f.amt/recipients.n,2) end,
 f.cat,f.proj,case when recipients.id is not null then case when recipients.name ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then recipients.name end when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then null else f.vrn end,
 case when recipients.id is not null then recipients.id when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then null else f.uid end,
 case when recipients.id is not null then recipients.name when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then null else f.uname end,
 case when recipients.id is not null then coalesce(recipients.grp,'Ej klassificerat') when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then 'Ej klassificerat' else f.grp end,
 f.src,f.descr,f.acc,f.fn,f.rn,
 f.raw||case when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then jsonb_build_object('_humla_distribution',jsonb_build_object('method','equal','scope',f.raw#>>'{_humla_assignment,shared_cost}','original_fact_id',f.fid,'original_amount',f.amt,'recipient_count',coalesce(recipients.n,0),'recipient_unit',recipients.id,'status',case when recipients.id is null then 'no_eligible_units' else 'allocated' end)) else '{}'::jsonb end
 from decorated f left join lateral(
 select eligible.*,count(*)over() n,row_number()over(order by eligible.id) position
 from (
  select distinct on(u.id) u.id,u.name,coalesce(own.name,registry.name) grp from unit_versions u
  left join lateral(select name from unit_group_versions g where g.unit_id=u.id and g.valid_from<=f.dt and (g.valid_to is null or g.valid_to>=f.dt) order by g.valid_from desc limit 1)own on true
  left join lateral(
   select case when count(distinct r.business_group)=1 then min(r.business_group) end name from public.kpi_project_classification_periods r
   where r.tenant_id=p_tenant_id and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt) and u.name=any(r.registrations) and r.business_group is not null
  )registry on own.name is null
  where f.k='cost' and f.src='NEXT' and f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','')
  and u.enabled and u.valid_from<=f.dt and (u.valid_to is null or u.valid_to>=f.dt)
  and (f.raw#>>'{_humla_assignment,shared_cost}'='*' or case when left(f.raw#>>'{_humla_assignment,shared_cost}',1)='[' then u.id::text in(select value from jsonb_array_elements_text((f.raw#>>'{_humla_assignment,shared_cost}')::jsonb)) else coalesce(own.name,registry.name)=f.raw#>>'{_humla_assignment,shared_cost}' end)
  order by u.id,u.valid_from desc
 )eligible
 )recipients on true;
end $function$;

CREATE OR REPLACE FUNCTION public.hub_kpi_match_queue_v2(p_tenant_id uuid, p_from date, p_to date, p_dimension text DEFAULT 'cost_center'::text, p_reference_type text DEFAULT 'project'::text, p_search text DEFAULT ''::text, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_dimension not in ('unresolved','all','cost_center','group','unit','vehicle','category','shared_cost') or p_reference_type not in ('project','vehicle','article','account','fact') or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 or p_page<0 then raise exception 'Ogiltigt urval';end if;
 with facts as materialized(select * from private.hub_kpi_filtered_classified_facts_v1(p_tenant_id,p_from,p_to,'{}'::jsonb)),
 rows as(
  select fact_id,occurred_on,kind,amount,project,vehicle,account,original,source,description,file_name,row_number,cost_center,business_group,unit_id::text unit_key,unit_name,category,false held from facts where case p_dimension when 'unresolved' then cost_center='unclassified' or business_group='Ej klassificerat' or unit_id is null or category='unclassified' when 'all' then true when 'cost_center' then cost_center='unclassified' when 'group' then business_group='Ej klassificerat' when 'unit' then unit_id is null when 'vehicle' then vehicle is null when 'shared_cost' then source='NEXT' and kind='cost' and project is not null else category in ('other','unclassified') end
  union all select r.id::text,r.occurred_on,r.data_kind,r.amount,r.project_reference,r.vehicle_registration,r.account,r.source_data,case when r.data_kind='cost' then 'NEXT' else 'Workify' end,r.description,(select b.file_name from public.kpi_import_batches b where b.id=r.batch_id and b.tenant_id=p_tenant_id),r.row_number,'unclassified','Ej klassificerat',null::text,null::text,'unclassified',true
  from public.kpi_import_rows r where r.tenant_id=p_tenant_id and not r.is_valid and r.data_kind in ('cost','revenue') and r.occurred_on between p_from and p_to and (p_dimension<>'shared_cost' or (r.data_kind='cost' and r.project_reference is not null))
 ), keyed as(select rows.*,named.project_name,named.registrations register_vehicles,case p_reference_type when 'project' then case when original?'_humla_original_project' then original->>'_humla_original_project' else project end when 'vehicle' then coalesce(original->>'_humla_original_registration',vehicle) when 'article' then nullif(original->>'Artikelnummer','') when 'account' then account else coalesce(original#>>'{_humla_distribution,original_fact_id}',fact_id) end reference from rows left join lateral(select r.project_name,r.registrations from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and r.project_reference=rows.project and r.valid_from<=rows.occurred_on and (r.valid_to is null or r.valid_to>=rows.occurred_on) order by r.valid_from desc,r.id limit 1)named on true),
 grouped as(select source,kind,coalesce(reference,fact_id) reference,case when reference is null then 'fact' else p_reference_type end reference_type,min(description) description,min(project_name) project_name,
coalesce(jsonb_agg(distinct vehicle)filter(where nullif(vehicle,'') is not null),'[]') vehicles,
coalesce(jsonb_agg(distinct to_jsonb(register_vehicles))filter(where register_vehicles is not null),'[]') register_vehicles,
coalesce(jsonb_agg(distinct jsonb_build_object('reference',project,'name',project_name))filter(where project is not null),'[]') projects,
coalesce(jsonb_agg(distinct account)filter(where account is not null),'[]') accounts,
coalesce(jsonb_agg(distinct original->>'Leverantör')filter(where original->>'Leverantör' is not null),'[]') suppliers,
coalesce(jsonb_agg(distinct cost_center),'[]') current_cost_centers,coalesce(jsonb_agg(distinct business_group),'[]') current_groups,coalesce(jsonb_agg(distinct unit_name)filter(where unit_name is not null),'[]') current_units,coalesce(jsonb_agg(distinct category),'[]') current_categories,bool_or(held) held,
jsonb_build_object('missing_vehicle',count(*) filter(where vehicle is null and project is null),'unit_conflict',count(*) filter(where (original#>>'{_humla_identity_resolution,unit_matches}')::int>1),'unit_missing',count(*) filter(where unit_key is null and vehicle is not null and coalesce((original#>>'{_humla_identity_resolution,unit_matches}')::int,0)<=1),'group_conflict',count(*) filter(where (original#>>'{_humla_identity_resolution,group_matches}')::int>1)) reasons,
jsonb_build_object('cost_center',count(*) filter(where cost_center='unclassified'),'group',count(*) filter(where business_group='Ej klassificerat'),'unit',count(*) filter(where unit_key is null),'category',count(*) filter(where category='unclassified'),'review',count(*) filter(where held)) missing,
count(*) rows,round(sum(amount),2) amount,min(occurred_on) first_date,max(occurred_on) last_date from keyed
 where concat_ws(' ',reference,project_name,description,source,account,project,vehicle,register_vehicles::text,original->>'Leverantör') ilike '%'||left(p_search,200)||'%' group by source,kind,coalesce(reference,fact_id),case when reference is null then 'fact' else p_reference_type end),
 page as(select * from grouped order by abs(amount) desc,source,kind,reference limit 100 offset p_page*100),
 sample_rows as(
 select k.*,row_number() over(partition by k.source,k.kind,coalesce(k.reference,k.fact_id),case when k.reference is null then 'fact' else p_reference_type end order by k.occurred_on,k.fact_id) sample_position
 from keyed k join page p on k.source=p.source and k.kind=p.kind and coalesce(k.reference,k.fact_id)=p.reference and (case when k.reference is null then 'fact' else p_reference_type end)=p.reference_type
 ), samples as(
 select source,kind,coalesce(reference,fact_id) reference,case when reference is null then 'fact' else p_reference_type end reference_type,
 jsonb_agg(jsonb_build_object('occurred_on',occurred_on,'amount',amount,'project',project,'project_name',project_name,'vehicle',vehicle,'account',account,'description',description,'file_name',file_name,'row_number',row_number,'original',original) order by sample_position)filter(where sample_position<=5) data
 from sample_rows group by source,kind,coalesce(reference,fact_id),case when reference is null then 'fact' else p_reference_type end
 )
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('samples',coalesce(s.data,'[]'))) from page p left join samples s using(source,kind,reference,reference_type)),'[]'),'total_groups',(select count(*)from grouped),'rows',(select coalesce(sum(rows),0)from grouped),'groups',(select coalesce(jsonb_agg(jsonb_build_object('name',name)order by name),'[]')from public.kpi_business_groups where tenant_id=p_tenant_id and enabled),
 'units',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name)order by name),'[]')from public.kpi_units where tenant_id=p_tenant_id and enabled and origin in ('manual','manual_builder')),
 'cost_centers',(select coalesce(jsonb_agg(to_jsonb(c)order by code),'[]')from(select cost_center code,min(cost_center_name)name from public.kpi_project_classification_periods where tenant_id=p_tenant_id group by cost_center)c),
 'history',(select coalesce(jsonb_agg(to_jsonb(h)),'[]')from(select dimension,source,kind,reference_type,reference,target,valid_from,valid_to,reason,created_at from public.kpi_dashboard_allocations where tenant_id=p_tenant_id order by created_at desc limit 50)h)) into result;
 return result;
end $function$
;