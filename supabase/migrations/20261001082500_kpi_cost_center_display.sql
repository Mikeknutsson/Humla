create function private.hub_kpi_cost_center_finance_v1(p_tenant_id uuid,p_from date,p_to date,p_cost_center text)
returns jsonb language sql stable security definer set search_path='' as $$
 with facts as materialized(select * from private.hub_kpi_classified_facts_v1(p_tenant_id,p_from,p_to) where cost_center=p_cost_center),
 totals as(select coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost,count(distinct vehicle) filter(where kind='revenue' and amount>0 and vehicle is not null) vehicle_count from facts),
 cats as(select category,round(sum(amount),2) amount from facts where kind='cost' group by category),
 vehicles as(select vehicle,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result,round(coalesce(sum(amount) filter(where kind='cost' and category='fuel'),0),2) fuel_cost,round(coalesce(sum(amount) filter(where source='TransPA'),0),2) personnel_cost from facts where vehicle is not null group by vehicle),
 groups as(select business_group key,business_group label,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by business_group)
 select jsonb_build_object('metrics',(select jsonb_build_object('revenue',round(revenue,2),'total_cost',round(cost,2),'result',round(revenue-cost,2),'margin_pct',round((revenue-cost)/nullif(revenue,0)*100,2),'revenue_per_vehicle',round(revenue/nullif(vehicle_count,0),2),'diesel_share',round((select coalesce(sum(amount),0) from facts where kind='cost' and category='fuel')/nullif(revenue,0)*100,2),'vehicle_utilization',null,'driver_billability',null) from totals),
 'components',(select jsonb_build_object('next_total_cost',round(coalesce(sum(amount) filter(where source='NEXT'),0),2),'transpa_personnel_cost',round(coalesce(sum(amount) filter(where source='TransPA'),0),2),'depreciation_cost',round(coalesce(sum(amount) filter(where category='depreciation' and kind='cost'),0),2)) from facts),
 'cost_categories',coalesce((select jsonb_object_agg(category,amount) from cats),'{}'),
 'vehicles',coalesce((select jsonb_agg(to_jsonb(v) order by vehicle) from vehicles v),'[]'),
 'business_groups',coalesce((select jsonb_agg(to_jsonb(g) order by label) from groups g),'[]'),
 'quality',(select jsonb_build_object('total_rows',count(*),'valid_rows',count(*),'rows_without_vehicle',count(*) filter(where vehicle is null),'rows_without_employee',null,'rows_without_account_mapping',null,'basis','authoritative_financial_facts_only') from facts),'drivers','[]'::jsonb,'unmapped_accounts','[]'::jsonb);
$$;
revoke all on function private.hub_kpi_cost_center_finance_v1(uuid,date,date,text) from public,anon;
grant execute on function private.hub_kpi_cost_center_finance_v1(uuid,date,date,text) to authenticated;

create function public.hub_kpi_cost_center_dashboard_v1(p_tenant_id uuid,p_from date,p_to date,p_cost_center text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare weekly jsonb; base jsonb; previous jsonb; details jsonb; options jsonb; filters jsonb; rev numeric; prev_rev numeric;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI-behörighet saknas' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_to<p_from then raise exception 'Ogiltig period'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('code',code,'name',name) order by code),'[]') into options from(select cost_center code,min(cost_center_name) name from public.kpi_project_classification_periods where tenant_id=p_tenant_id group by cost_center union all select 'unclassified','Ej klassificerat') x;
 if p_cost_center is not null and not exists(select 1 from jsonb_array_elements(options) o where o->>'code'=p_cost_center) then raise exception 'Okänt kostnadsställe'; end if;
 filters:=case when p_cost_center is null then '{}'::jsonb else jsonb_build_object('cost_center',p_cost_center) end;
 details:=public.hub_kpi_analysis_v2(p_tenant_id,p_from,p_to,filters,'group','month',0,false);
 if p_cost_center is null then
  base:=public.hub_kpi_dashboard_display_v1(p_tenant_id,p_from,p_to);
  base:=base||jsonb_build_object('business_groups',details->'groups');
 else
  base:=private.hub_kpi_cost_center_finance_v1(p_tenant_id,p_from,p_to,p_cost_center);
  if exists(select 1 from public.kpi_project_classification_periods where tenant_id=p_tenant_id and cost_center=p_cost_center and valid_from<=(p_from-interval '1 year')::date and (valid_to is null or valid_to>=(p_to-interval '1 year')::date)) then
   previous:=private.hub_kpi_cost_center_finance_v1(p_tenant_id,(p_from-interval '1 year')::date,(p_to-interval '1 year')::date,p_cost_center);
  end if;
  rev:=(base->'metrics'->>'revenue')::numeric;prev_rev:=(previous->'metrics'->>'revenue')::numeric;
  base:=jsonb_set(base,'{metrics,revenue_change_pct}',coalesce(to_jsonb(round((rev-prev_rev)/nullif(prev_rev,0)*100,2)),'null'::jsonb));
  weekly:=public.hub_kpi_analysis_v2(p_tenant_id,p_from,p_to,filters,'group','week',0,false);
  base:=base||jsonb_build_object('weekly',jsonb_build_object('weeks',(select coalesce(jsonb_agg(jsonb_build_object('week_start',w->>'period_start','revenue',w->'revenue','previous_revenue',null)),'[]') from jsonb_array_elements(weekly->'periods') w)));
  base:=base||jsonb_build_object('previous',previous,'personnel_basis','TransPA-tid × Hub-schablon; inte verifierad löneexport','cost_efficiency','{}'::jsonb,'efficiency',null,'transpa_vehicle_time',null,'hired_capacity',null,'driver_productivity',null,'scoped_operational_unavailable',true,'repair_summary',null);
 end if;
 return base||jsonb_build_object('cost_centers',options,'cost_center_scope',p_cost_center,'classification_valid_from',(select min(valid_from) from public.kpi_project_classification_periods where tenant_id=p_tenant_id),'reconciliation',jsonb_build_object('matches',(base->'metrics'->>'revenue')::numeric=(details->'summary'->>'revenue')::numeric and (base->'metrics'->>'total_cost')::numeric=(details->'summary'->>'cost')::numeric,'source','Hub authoritative facts, dated classification','details',details->'summary'));
end $$;
revoke all on function public.hub_kpi_cost_center_dashboard_v1(uuid,date,date,text) from public,anon;
grant execute on function public.hub_kpi_cost_center_dashboard_v1(uuid,date,date,text) to authenticated;
