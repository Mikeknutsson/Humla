-- One prepared financial ledger for Overview, KPI, reports, export and drilldown.
-- Source transactions/reviews remain untouched. Tank purchases remain available
-- as zero-impact reconciliation rows rather than counting fuel twice.
create function private.hub_kpi_prepare_piusi_facts_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql set search_path='' as $$
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
 set original=f.original||jsonb_build_object('_humla_fuel_reconciliation',jsonb_build_object('booked_amount',f.amount,'reason','Egen tank: Piusi consumption is the cost basis for this month')),
 display_original=f.display_original||jsonb_build_object('_humla_fuel_reconciliation',jsonb_build_object('booked_amount',f.amount)),amount=0
 where f.generation_id=p_generation and f.source='NEXT' and f.kind='cost' and f.category='fuel' and f.account='5360'
 and exists(select 1 from private.hub_kpi_prepared_hub_objects o where o.generation_id=p_generation and o.tenant_id=p_tenant and o.object_type='FuelTransaction' and o.data->>'source_system'='piusi_bsmart'
 and date_trunc('month',(o.data->>'transaction_date')::timestamp)::date=date_trunc('month',f.occurred_on)::date);
end $$;
revoke all on function private.hub_kpi_prepare_piusi_facts_v1(uuid,uuid) from public,anon,authenticated;

do $patch$ declare definition text; needle text; begin
 select pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure) into definition;
 needle:=' insert into private.hub_kpi_prepared_display_facts select';
 if position(needle in definition)=0 then raise exception 'Prepared worker changed';end if;
 execute replace(definition,needle,' perform private.hub_kpi_prepare_piusi_facts_v1(job.tenant_id,generation);'||chr(10)||needle);
 -- The fuel evidence RPC must read NEXT only; prepared Piusi is already present
 -- in the common ledger and must not be unioned as an additional NEXT row.
 select pg_get_functiondef('private.hub_kpi_monthly_fuel_sources_v1(uuid,integer,integer[],jsonb)'::regprocedure) into definition;
 needle:='from facts f where kind=''cost'' and category=''fuel''';
 if position(needle in definition)=0 then raise exception 'Fuel evidence contract changed';end if;
 definition:=replace(definition,needle,'from facts f where source=''NEXT'' and kind=''cost'' and category=''fuel''');
 definition:=replace(definition,'sum(amount),0),2) from next_fuel where not include_cost','sum(coalesce((original#>>''{_humla_fuel_reconciliation,booked_amount}'')::numeric,amount)),0),2) from next_fuel where not include_cost');
 needle:='select ''Piusi'' source,id::text id,dt,reg vehicle,accepted_cost amount,liters,price_status,data->>''product_name'' product,unit_key from scoped';
 if position(needle in definition)=0 then raise exception 'Fuel evidence union changed';end if;
 definition:=replace(definition,needle,'select ''Piusi'' source,fact_id id,occurred_on dt,vehicle,amount,(original#>>''{_humla_fuel,quantity_liters}'')::numeric liters,original#>>''{_humla_fuel,price_status}'' price_status,original->>''product_name'' product,coalesce(unit_id::text,''vehicle:''||vehicle,''unassigned'') unit_key from facts where source=''Piusi''');
 definition:=replace(definition,'sum(accepted_cost),2) from scoped','sum(amount),2) from facts where source=''Piusi''');
 definition:=replace(definition,'sum(liters) filter(where liters>0),2) from scoped','sum((original#>>''{_humla_fuel,quantity_liters}'')::numeric),2) from facts where source=''Piusi''');
 execute definition;
 -- Month drilldown previously recalculated live rows, unlike all other reports.
 -- Use the same frozen generation and retain the exact month selection.
 select pg_get_functiondef('public.hub_kpi_analysis_months_v1(uuid,date,date,jsonb,text,text,integer,boolean)'::regprocedure) into definition;
 needle:='private.hub_kpi_month_facts_v1(p_tenant_id,fiscal_year,months,p_filters)';
 if position(needle in definition)=0 then raise exception 'Month drilldown changed';end if;
 execute replace(definition,needle,'private.hub_kpi_prepared_range_facts_v1(p_tenant_id,make_date(fiscal_year,9,1),make_date(fiscal_year+1,8,31)) where extract(month from occurred_on)::int=any(months)');
 -- Surface Piusi as an explicit component; no frontend sum is needed.
 select pg_get_functiondef('private.hub_kpi_prepared_snapshot_v1(uuid,integer,integer[],jsonb)'::regprocedure) into definition;
 needle:='''next_total_cost'',round(coalesce(sum(amount) filter(where source=''NEXT''),0),2)';
 if position(needle in definition)=0 then raise exception 'Snapshot components changed';end if;
 definition:=replace(definition,needle,'''piusi_fuel_cost'',round(coalesce(sum(amount) filter(where source=''Piusi''),0),2),'||needle);
 needle:='''time_report_id'',original->''time_report_id'',''_humla_distribution''';
 if position(needle in definition)=0 then raise exception 'Snapshot projection changed';end if;
 definition:=replace(definition,needle,'''_humla_fuel'',original->''_humla_fuel'',''time_report_id'',original->''time_report_id'',''_humla_distribution''');
 needle:=' unit_performance as(select';
 if position(needle in definition)=0 then raise exception 'Unit performance changed';end if;
 definition:=replace(definition,needle,' unit_fuel_quantity as(select coalesce(unit_id::text,''vehicle:''||vehicle,''unassigned'') key,case when bool_and(source=''Piusi'' or amount=0) then sum((original#>>''{_humla_fuel,quantity_liters}'')::numeric) end liters from facts where kind=''cost'' and category=''fuel'' group by 1),'||chr(10)||needle);
 definition:=replace(definition,'''fuel_liters_per_mil'',null','''fuel_liters_per_mil'',round(q.liters/nullif(d.distance_mil,0),2)');
 definition:=replace(definition,'from units u left join unit_categories c','from units u left join unit_fuel_quantity q on q.key=u.key left join unit_categories c');
 execute definition;
end $patch$;
