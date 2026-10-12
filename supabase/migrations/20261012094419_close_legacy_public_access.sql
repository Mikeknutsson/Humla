-- Close legacy anonymous access, enforce tenant isolation and preserve authorized reports.
alter table public.kpi_business_groups enable row level security;
revoke all on public.kpi_business_groups from public,anon;
create policy legacy_tenant_read on public.kpi_business_groups for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));
create policy legacy_tenant_manage on public.kpi_business_groups for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
alter table public.kpi_project_business_groups enable row level security;
revoke all on public.kpi_project_business_groups from public,anon;
create policy legacy_tenant_read on public.kpi_project_business_groups for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));
create policy legacy_tenant_manage on public.kpi_project_business_groups for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
alter table public.kpi_asset_depreciation_periods enable row level security;
revoke all on public.kpi_asset_depreciation_periods from public,anon;
create policy legacy_tenant_read on public.kpi_asset_depreciation_periods for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));
create policy legacy_tenant_manage on public.kpi_asset_depreciation_periods for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
alter table public.kpi_cost_project_category_rules enable row level security;
revoke all on public.kpi_cost_project_category_rules from public,anon;
create policy legacy_tenant_read on public.kpi_cost_project_category_rules for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));
create policy legacy_tenant_manage on public.kpi_cost_project_category_rules for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
alter table public.kpi_cost_category_rules enable row level security;
revoke all on public.kpi_cost_category_rules from public,anon;
create policy legacy_tenant_read on public.kpi_cost_category_rules for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));
create policy legacy_tenant_manage on public.kpi_cost_category_rules for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
alter table public.hub_material_purchase_prices enable row level security;
revoke all on public.hub_material_purchase_prices from public,anon;
create policy legacy_tenant_read on public.hub_material_purchase_prices for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));
create policy legacy_tenant_manage on public.hub_material_purchase_prices for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
alter table public.hub_identity_redirects enable row level security;
revoke all on public.hub_identity_redirects from public,anon;
create policy legacy_tenant_read on public.hub_identity_redirects for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));
revoke insert,update,delete,truncate,references,trigger on public.hub_identity_redirects from authenticated;
alter table public.hub_cost_allocation_review enable row level security;
revoke all on public.hub_cost_allocation_review from public,anon;
create policy legacy_tenant_read on public.hub_cost_allocation_review for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));
create policy legacy_tenant_manage on public.hub_cost_allocation_review for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
alter table public.hub_cost_allocation_rules enable row level security;
revoke all on public.hub_cost_allocation_rules from public,anon;
create policy legacy_tenant_read on public.hub_cost_allocation_rules for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));
create policy legacy_tenant_manage on public.hub_cost_allocation_rules for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
alter table public.hub_salaried_staff_cost_settings enable row level security;
revoke all on public.hub_salaried_staff_cost_settings from public,anon;
create policy legacy_tenant_read on public.hub_salaried_staff_cost_settings for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
create policy legacy_tenant_manage on public.hub_salaried_staff_cost_settings for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
alter table public.hub_salaried_staff_allocations enable row level security;
revoke all on public.hub_salaried_staff_allocations from public,anon;
create policy legacy_tenant_read on public.hub_salaried_staff_allocations for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
create policy legacy_tenant_manage on public.hub_salaried_staff_allocations for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
alter table public.hub_cost_project_allocations enable row level security;
revoke all on public.hub_cost_project_allocations from public,anon;
create policy legacy_tenant_read on public.hub_cost_project_allocations for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));
create policy legacy_tenant_manage on public.hub_cost_project_allocations for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.manage'));
alter table public.hub_sync_policy enable row level security;
revoke all on public.hub_sync_policy from public,anon;
create policy legacy_tenant_read on public.hub_sync_policy for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'hub.connections.manage'));
create policy legacy_tenant_manage on public.hub_sync_policy for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'hub.connections.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'hub.connections.manage'));
alter table public.hub_connection_sync_settings enable row level security;
revoke all on public.hub_connection_sync_settings from public,anon;
create policy legacy_tenant_read on public.hub_connection_sync_settings for select to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'hub.connections.manage'));
create policy legacy_tenant_manage on public.hub_connection_sync_settings for all to authenticated using (auth.uid() is not null and public.hub_has_permission(tenant_id,'hub.connections.manage')) with check (auth.uid() is not null and public.hub_has_permission(tenant_id,'hub.connections.manage'));
alter table public.humla_architecture_rules enable row level security;
revoke all on public.humla_architecture_rules from public,anon;
revoke insert,update,delete,truncate,references,trigger on public.humla_architecture_rules from authenticated;
create policy architecture_authenticated_read on public.humla_architecture_rules for select to authenticated using ((select auth.uid()) is not null);
alter view public.kpi_transpa_vehicle_time_daily set (security_invoker=true);
revoke all on public.kpi_transpa_vehicle_time_daily from public,anon;
alter view public.hub_flow_operational_status_v1 set (security_invoker=true);
revoke all on public.hub_flow_operational_status_v1 from public,anon;
alter view public.hub_identity_quality_v1 set (security_invoker=true);
revoke all on public.hub_identity_quality_v1 from public,anon;
alter view public.hub_workify_material_sales_v1 set (security_invoker=true);
revoke all on public.hub_workify_material_sales_v1 from public,anon;
alter view public.hub_identity_canonical_keys_v1 set (security_invoker=true);
revoke all on public.hub_identity_canonical_keys_v1 from public,anon;
alter view public.hub_control_center_identity_quality_v1 set (security_invoker=true);
revoke all on public.hub_control_center_identity_quality_v1 from public,anon;
alter view public.hub_control_center_review_counts_v1 set (security_invoker=true);
revoke all on public.hub_control_center_review_counts_v1 from public,anon;
alter view public.hub_cost_allocation_rule_overview_v1 set (security_invoker=true);
revoke all on public.hub_cost_allocation_rule_overview_v1 from public,anon;
alter view public.hub_salaried_staff_allocation_quality_v1 set (security_invoker=true);
revoke all on public.hub_salaried_staff_allocation_quality_v1 from public,anon;
alter view public.hub_common_cost_rules_v1 set (security_invoker=true);
revoke all on public.hub_common_cost_rules_v1 from public,anon;
CREATE OR REPLACE FUNCTION public.hub_kpi_admin_projects_v1(p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with p as(select distinct coalesce(r.allocation->>'allocation_reference',r.project_reference) ref from public.kpi_import_rows r where r.tenant_id=p_tenant_id and r.data_kind='cost' and coalesce(r.allocation->>'allocation_reference',r.project_reference) is not null), x as(select p.ref,pm.project_name,bg.id group_id,bg.name group_name from p left join lateral(select min(project_name) project_name from public.kpi_project_unit_mappings m where m.tenant_id=p_tenant_id and m.project_reference=p.ref) pm on true left join public.kpi_project_business_groups pbg on pbg.tenant_id=p_tenant_id and pbg.project_reference=p.ref left join public.kpi_business_groups bg on bg.id=pbg.business_group_id) select coalesce(jsonb_agg(jsonb_build_object('project_reference',ref,'project_name',project_name,'business_group_id',group_id,'business_group',coalesce(group_name,'Ej klassificerat')) order by ref),'[]'::jsonb) from x);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_admin_unit_builder_v1(p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with p as(select u.id,u.name,u.unit_type,u.projects,(regexp_match(u.name,'([A-ZÅÄÖ]{3}[0-9]{2}[A-ZÅÄÖ])'))[1] registration from public.kpi_units u where u.tenant_id=p_tenant_id and u.origin='next_project_import' and u.unit_type='vehicle'), c as(select unit_id,count(*) n,jsonb_agg(jsonb_build_object('type',component_type,'reference',component_reference,'allocation_percent',allocation_percent)) components from public.kpi_unit_components where tenant_id=p_tenant_id group by unit_id) select jsonb_build_object('candidates',coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'registration',p.registration,'projects',p.projects,'component_count',coalesce(c.n,0),'components',coalesce(c.components,'[]'::jsonb)) order by p.name),'[]'::jsonb)) from p left join c on c.unit_id=p.id);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_next_vehicle_costs_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with mappings as (
 select project_reference,
        case when count(distinct upper(trim(vehicle_registration)))=1 then max(upper(trim(vehicle_registration))) end vehicle
 from public.kpi_project_unit_mappings
 where tenant_id=p_tenant_id and enabled
 group by project_reference
),
rows as (
 select r.id,r.amount,r.account,
        coalesce(r.allocation->>'allocation_reference',r.project_reference) project_reference,
        coalesce(r.allocation->>'allocation_status','') allocation_status,
        m.vehicle
 from public.kpi_import_rows r
 left join mappings m on m.project_reference=coalesce(r.allocation->>'allocation_reference',r.project_reference)
 where r.tenant_id=p_tenant_id and r.data_kind='cost' and r.is_valid
   and r.occurred_on between p_from and p_to
   and coalesce(r.account,'') not in ('4015','4425')
   and public.hub_has_permission(p_tenant_id,'kpi.read')
),
agg as (
 select vehicle,
   sum(amount) filter(where account in('5360','5621','5631')) fuel_cost,
   sum(amount) filter(where account not in('5360','5621','5631')) other_cost,
   count(*) row_count
 from rows where vehicle is not null and allocation_status='identified' group by vehicle
),
tot as (
 select coalesce(sum(amount) filter(where vehicle is null or allocation_status<>'identified'),0) unallocated_cost from rows
)
select jsonb_build_object(
 'vehicles',coalesce((select jsonb_agg(jsonb_build_object('vehicle',vehicle,'cost',coalesce(other_cost,0),'fuel_cost',coalesce(fuel_cost,0),'rows',row_count) order by vehicle) from agg),'[]'::jsonb),
 'mapped_other_cost',coalesce((select sum(other_cost) from agg),0),
 'mapped_fuel_cost',coalesce((select sum(fuel_cost) from agg),0),
 'unallocated_cost',(select unallocated_cost from tot)
));
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_profit_by_category_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with wr as(select coalesce(ar.revenue_category,'unclassified') category,sum(x.amount) revenue from public.kpi_import_rows x left join lateral(select a.revenue_category from public.kpi_workify_article_rules a where a.tenant_id=p_tenant_id and a.enabled and a.article_number=coalesce(x.source_data->>'Artikelnummer','') and x.occurred_on>=a.valid_from and (a.valid_to is null or x.occurred_on<=a.valid_to) order by a.valid_from desc limit 1) ar on true where x.tenant_id=p_tenant_id and x.data_kind='revenue' and x.is_valid and x.occurred_on between p_from and p_to group by 1), nc as(select coalesce(cr.cost_category,case when x.project_reference='9009' then 'transport' when x.account in('5360','5621','5631') then 'transport' else 'unclassified' end) category,sum(x.amount) cost from public.kpi_import_rows x left join lateral(select c.cost_category from public.kpi_cost_category_rules c where c.tenant_id=p_tenant_id and c.account=x.account and x.occurred_on>=c.valid_from and (c.valid_to is null or x.occurred_on<=c.valid_to) order by c.valid_from desc limit 1)cR on true where x.tenant_id=p_tenant_id and x.data_kind='cost' and x.is_valid and x.occurred_on between p_from and p_to group by 1), cats as(select category from wr union select category from nc), a as(select c.category,coalesce(w.revenue,0) revenue,coalesce(n.cost,0) cost from cats c left join wr w using(category) left join nc n using(category)) select jsonb_build_object('categories',coalesce(jsonb_agg(jsonb_build_object('category',category,'revenue',revenue,'cost',cost,'result',revenue-cost,'margin_pct',case when revenue=0 then 0 else round(((revenue-cost)/revenue*100)::numeric,2) end) order by category),'[]'::jsonb),'total_revenue',coalesce(sum(revenue),0),'total_cost',coalesce(sum(cost),0),'total_result',coalesce(sum(revenue-cost),0)) from a);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_transport_dashboard_v4(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with rev as(select public.hub_kpi_workify_revenue_allocation_v1(p_tenant_id,p_from,p_to) j), cb as(select public.hub_kpi_cost_buckets_v2(p_tenant_id,p_from,p_to) j), per as(select public.hub_kpi_personnel_costs_engine_v1(p_tenant_id,p_from,p_to) j), dep as(select public.hub_kpi_depreciation_engine_v1(p_tenant_id,p_from,p_to) j), bg as(select public.hub_kpi_business_group_costs_v2(p_tenant_id,p_from,p_to) j), vals as(select coalesce((rev.j->>'total_revenue')::numeric,0) revenue,coalesce((cb.j->>'total_next_cost')::numeric,0) next_cost,coalesce((per.j->>'total_personnel_cost')::numeric,0) transpa_personnel,coalesce((dep.j->>'total_depreciation_cost')::numeric,0) depreciation from rev,cb,per,dep) select jsonb_build_object('hub_contract_version',4,'period',jsonb_build_object('from',p_from,'to',p_to),'metrics',jsonb_build_object('revenue',round(v.revenue,2),'total_cost',round(v.next_cost+v.transpa_personnel+v.depreciation,2),'result',round(v.revenue-v.next_cost-v.transpa_personnel-v.depreciation,2),'margin_pct',case when v.revenue=0 then 0 else round(((v.revenue-v.next_cost-v.transpa_personnel-v.depreciation)/v.revenue*100)::numeric,2) end),'components',jsonb_build_object('next_total_cost',round(v.next_cost,2),'transpa_personnel_cost',round(v.transpa_personnel,2),'depreciation_cost',round(v.depreciation,2)),'cost_categories',cb.j->'buckets','revenue_categories',rev.j->'categories','business_groups',bg.j->'groups','revenue_allocation',rev.j,'personnel',per.j,'depreciation',dep.j) from vals v,rev,cb,per,dep,bg);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_transport_dashboard_v2(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with b as(select public.kpi_transport_dashboard(p_tenant_id,p_from,p_to) j),n as(select public.hub_kpi_next_costs_engine_v2(p_tenant_id,p_from,p_to) j),p as(select public.hub_kpi_personnel_costs_engine_v1(p_tenant_id,p_from,p_to) j) select jsonb_build_object('period',b.j->'period','metrics',(b.j->'metrics')||jsonb_build_object('result',coalesce((b.j#>>'{metrics,revenue}')::numeric,0)-coalesce((n.j->>'total_next_cost')::numeric,0)-coalesce((p.j->>'total_personnel_cost')::numeric,0),'margin_pct',case when coalesce((b.j#>>'{metrics,revenue}')::numeric,0)<>0 then (coalesce((b.j#>>'{metrics,revenue}')::numeric,0)-coalesce((n.j->>'total_next_cost')::numeric,0)-coalesce((p.j->>'total_personnel_cost')::numeric,0))/((b.j#>>'{metrics,revenue}')::numeric)*100 else 0 end),'components',jsonb_build_object('next_total_cost',n.j->'total_next_cost','hired_trucks_cost',n.j->'hired_trucks_cost','vehicle_total_cost',n.j->'vehicle_total_cost','other_unallocated_cost',n.j->'other_unallocated_cost','personnel_cost',p.j->'total_personnel_cost'),'base',b.j,'next',n.j,'personnel',p.j) from b,n,p);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_cost_buckets_v2(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with x as (select r.amount, case when r.project_reference='9009' then 'hired' when r.project_reference='5100' then 'tipp_deponi' when r.account in ('5360','5621','5631') then 'fuel' else coalesce((select c.cost_category from public.kpi_cost_category_rules c where c.tenant_id=p_tenant_id and c.account=r.account and r.occurred_on>=c.valid_from and (c.valid_to is null or r.occurred_on<=c.valid_to) order by c.valid_from desc limit 1),'other') end bucket from public.kpi_import_rows r where r.tenant_id=p_tenant_id and r.data_kind='cost' and r.is_valid and r.occurred_on between p_from and p_to), a as(select bucket,sum(amount) amount,count(*) rows from x group by bucket) select jsonb_build_object('total_next_cost',coalesce(sum(amount),0),'buckets',coalesce(jsonb_agg(jsonb_build_object('category',bucket,'amount',round(amount,2),'rows',rows) order by bucket),'[]'::jsonb)) from a);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_business_group_costs_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with r as(select coalesce(x.allocation->>'allocation_reference',x.project_reference) project_reference,x.amount from public.kpi_import_rows x where x.tenant_id=p_tenant_id and x.data_kind='cost' and x.is_valid and x.occurred_on between p_from and p_to),g as(select r.*,coalesce(bg.name,'Ej klassificerat') business_group from r left join public.kpi_project_business_groups pbg on pbg.tenant_id=p_tenant_id and pbg.project_reference=r.project_reference left join public.kpi_business_groups bg on bg.id=pbg.business_group_id and bg.enabled),a as(select business_group,sum(amount) cost,count(*) rows from g group by business_group) select jsonb_build_object('groups',coalesce(jsonb_agg(jsonb_build_object('name',business_group,'cost',cost,'rows',rows) order by business_group),'[]'::jsonb),'total_cost',coalesce(sum(cost),0)) from a);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_personnel_costs_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with defaults as (
 select coalesce(monthly_salary,34000)::numeric monthly_salary,coalesce(weekly_hours,40)::numeric weekly_hours,coalesce(overtime_multiplier,1.5)::numeric overtime_multiplier,coalesce(employer_contribution_pct,31.42)::numeric employer_pct,coalesce(pension_pct,4.5)::numeric pension_pct,coalesce(other_overhead_pct,0)::numeric overhead_pct from public.kpi_personnel_salary_settings where tenant_id=p_tenant_id and is_default limit 1
), d as(select * from defaults union all select 34000::numeric,40::numeric,1.5::numeric,31.42::numeric,4.5::numeric,0::numeric where not exists(select 1 from defaults)),
facts as(select f.*,coalesce(s.monthly_salary,d.monthly_salary)::numeric salary,coalesce(s.weekly_hours,d.weekly_hours)::numeric weekly_hours,coalesce(s.overtime_multiplier,d.overtime_multiplier)::numeric ot_mult,(1+(coalesce(s.employer_contribution_pct,d.employer_pct)+coalesce(s.pension_pct,d.pension_pct)+coalesce(s.other_overhead_pct,d.overhead_pct))/100)::numeric load_factor,date_trunc('week',f.work_date)::date week_start from public.kpi_transpa_time_facts f cross join d left join public.kpi_personnel_salary_settings s on s.tenant_id=f.tenant_id and s.transpa_employee_id=f.employee_id and not s.is_default where f.tenant_id=p_tenant_id and f.work_date between p_from and p_to and f.work_hours>0),
weekly as(select employee_id,week_start,sum(work_hours) total_hours,max(weekly_hours) weekly_hours from facts group by employee_id,week_start),
costed0 as(select f.*, (f.salary/(f.weekly_hours*52/12)) hourly,case when w.total_hours<=f.weekly_hours then f.work_hours else f.work_hours*(f.weekly_hours/w.total_hours) end regular_hours,case when w.total_hours<=f.weekly_hours then 0 else f.work_hours*((w.total_hours-f.weekly_hours)/w.total_hours) end overtime_hours from facts f join weekly w using(employee_id,week_start)),
costed as(select c.*,((c.regular_hours*c.hourly)+(c.overtime_hours*c.hourly*c.ot_mult))*c.load_factor personnel_cost from costed0 c),
expanded as(select c.*,j.value#>>'{}' vehicle_id from costed c left join lateral jsonb_array_elements(c.transpa_vehicle_ids) j(value) on true),
veh as(select e.external_id,e.payload->>'registrationNumber' registration from public.hub_transpa_entities e where e.tenant_id=p_tenant_id and e.entity_type='vehicle'),
by_vehicle as(select upper(trim(v.registration)) vehicle,sum(e.personnel_cost/nullif(jsonb_array_length(e.transpa_vehicle_ids),0)) personnel_cost,sum(e.work_hours/nullif(jsonb_array_length(e.transpa_vehicle_ids),0)) work_hours from expanded e join veh v on v.external_id=e.vehicle_id where v.registration is not null group by 1)
select case when public.hub_has_permission(p_tenant_id,'kpi.read') then jsonb_build_object('total_personnel_cost',coalesce((select sum(personnel_cost) from costed),0),'vehicles',coalesce((select jsonb_agg(jsonb_build_object('vehicle',vehicle,'personnel_cost',round(personnel_cost,2),'work_hours',round(work_hours,2)) order by vehicle) from by_vehicle),'[]'::jsonb),'unallocated_cost',coalesce((select sum(personnel_cost) from costed where jsonb_array_length(transpa_vehicle_ids)=0),0)) else jsonb_build_object('total_personnel_cost',0,'vehicles','[]'::jsonb,'unallocated_cost',0) end);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_personnel_costs_engine_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with d as (select coalesce(monthly_salary,34000)::numeric salary,coalesce(weekly_hours,40)::numeric weekly_hours,coalesce(overtime_multiplier,1.5)::numeric ot_mult,(1+(coalesce(employer_contribution_pct,31.42)+coalesce(pension_pct,4.5)+coalesce(other_overhead_pct,0))/100)::numeric load_factor from public.kpi_personnel_salary_settings where tenant_id=p_tenant_id and is_default limit 1), cfg as(select * from d union all select 34000,40,1.5,1.3592 where not exists(select 1 from d)), f as(select t.*,c.salary,c.weekly_hours,c.ot_mult,c.load_factor,date_trunc('week',work_date)::date wk from public.kpi_transpa_time_facts t cross join cfg c where t.tenant_id=p_tenant_id and t.work_date between p_from and p_to and t.work_hours>0), w as(select employee_id,wk,sum(work_hours) wh from f group by 1,2), c as(select f.*,salary/(weekly_hours*52/12) rate,case when w.wh<=weekly_hours then work_hours else work_hours*weekly_hours/w.wh end rh,case when w.wh<=weekly_hours then 0 else work_hours*(w.wh-weekly_hours)/w.wh end oh from f join w using(employee_id,wk)), x as(select c.*,((rh*rate)+(oh*rate*ot_mult))*load_factor pc,j.value#>>'{}' vid from c left join lateral jsonb_array_elements(transpa_vehicle_ids) j(value) on true), v as(select external_id,payload->>'registrationNumber' reg from public.hub_transpa_entities where tenant_id=p_tenant_id and entity_type='vehicle'), a as(select upper(trim(v.reg)) vehicle,sum(x.pc/nullif(jsonb_array_length(x.transpa_vehicle_ids),0)) cost from x join v on v.external_id=x.vid group by 1) select jsonb_build_object('total_personnel_cost',coalesce((select sum(pc) from (select distinct time_report_id,pc from x) z),0),'vehicles',coalesce((select jsonb_agg(jsonb_build_object('vehicle',vehicle,'personnel_cost',round(cost,2)) order by vehicle) from a),'[]'::jsonb)));
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_next_costs_engine_v2(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with m as (select project_reference,case when count(distinct upper(trim(vehicle_registration)))=1 then max(upper(trim(vehicle_registration))) end vehicle from public.kpi_project_unit_mappings where tenant_id=p_tenant_id and enabled group by project_reference), r as (select x.amount,x.account,coalesce(x.allocation->>'allocation_reference',x.project_reference) project_reference,m.vehicle from public.kpi_import_rows x left join m on m.project_reference=coalesce(x.allocation->>'allocation_reference',x.project_reference) where x.tenant_id=p_tenant_id and x.data_kind='cost' and x.is_valid and x.occurred_on between p_from and p_to), c as (select *,account in('5360','5621','5631') is_fuel,case when project_reference='9009' then 'hired_trucks' when vehicle is not null then 'vehicle' else 'other_unallocated' end bucket from r), v as(select vehicle,sum(amount) filter(where not is_fuel) other_cost,sum(amount) filter(where is_fuel) fuel_cost,sum(amount) total_cost from c where bucket='vehicle' group by vehicle) select jsonb_build_object('total_next_cost',coalesce(sum(amount),0),'hired_trucks_cost',coalesce(sum(amount) filter(where bucket='hired_trucks'),0),'vehicle_total_cost',coalesce(sum(amount) filter(where bucket='vehicle'),0),'other_unallocated_cost',coalesce(sum(amount) filter(where bucket='other_unallocated'),0),'vehicles',coalesce((select jsonb_agg(jsonb_build_object('vehicle',vehicle,'other_cost',coalesce(other_cost,0),'fuel_cost',coalesce(fuel_cost,0),'total_cost',total_cost) order by vehicle) from v),'[]'::jsonb)) from c);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_unit_rollup_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with n as(select public.hub_kpi_next_costs_engine_v2(p_tenant_id,p_from,p_to) j), nv as(select upper(trim(x->>'vehicle')) vehicle,coalesce((x->>'other_cost')::numeric,0) other_cost,coalesce((x->>'fuel_cost')::numeric,0) fuel_cost,coalesce((x->>'total_cost')::numeric,0) total_cost from n cross join lateral jsonb_array_elements(n.j->'vehicles') x), units as(select u.id,u.name,upper(trim(r)) main_vehicle from public.kpi_units u cross join lateral unnest(u.registrations) r where u.tenant_id=p_tenant_id and u.enabled and u.unit_type='compound'), comps as(select u.id unit_id,u.name unit_name,u.main_vehicle,c.component_reference from units u left join public.kpi_unit_components c on c.tenant_id=p_tenant_id and c.unit_id=u.id and (c.valid_from is null or c.valid_from<=p_to) and (c.valid_to is null or c.valid_to>=p_from)), roll as(select c.unit_id,c.unit_name,c.main_vehicle,sum(coalesce(v.other_cost,0)) other_cost,sum(coalesce(v.fuel_cost,0)) fuel_cost,sum(coalesce(v.total_cost,0)) total_cost from comps c left join nv v on v.vehicle=upper(trim(c.component_reference)) or v.vehicle=c.main_vehicle group by c.unit_id,c.unit_name,c.main_vehicle) select jsonb_build_object('units',coalesce(jsonb_agg(jsonb_build_object('id',unit_id,'name',unit_name,'main_vehicle',main_vehicle,'other_cost',other_cost,'fuel_cost',fuel_cost,'total_cost',total_cost) order by unit_name),'[]'::jsonb)) from roll);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_transport_dashboard_v3(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with d as(select public.hub_kpi_transport_dashboard_v2(p_tenant_id,p_from,p_to) j),g as(select public.hub_kpi_business_group_costs_v1(p_tenant_id,p_from,p_to) j),u as(select public.hub_kpi_unit_rollup_v1(p_tenant_id,p_from,p_to) j) select d.j||jsonb_build_object('business_groups',g.j->'groups','compound_units',u.j->'units','hub_contract_version',3) from d,g,u);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_business_group_costs_v2(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with r as(select x.occurred_on,coalesce(x.allocation->>'allocation_reference',x.project_reference) project_reference,x.amount from public.kpi_import_rows x where x.tenant_id=p_tenant_id and x.data_kind='cost' and x.is_valid and x.occurred_on between p_from and p_to),g as(select r.*,coalesce(bg.name,'Ej klassificerat') business_group from r left join lateral(select pbg.business_group_id from public.kpi_project_business_groups pbg where pbg.tenant_id=p_tenant_id and pbg.project_reference=r.project_reference and r.occurred_on>=coalesce(pbg.valid_from,'2000-01-01') and (pbg.valid_to is null or r.occurred_on<=pbg.valid_to) order by pbg.valid_from desc limit 1)p on true left join public.kpi_business_groups bg on bg.id=p.business_group_id and bg.enabled),a as(select business_group,sum(amount) cost,count(*) rows from g group by business_group) select jsonb_build_object('groups',coalesce(jsonb_agg(jsonb_build_object('name',business_group,'cost',cost,'rows',rows) order by business_group),'[]'::jsonb),'total_cost',coalesce(sum(cost),0)) from a);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_depreciation_engine_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with m as(select d.object_reference,d.monthly_depreciation,gs::date month_start from public.kpi_asset_depreciation_periods d cross join lateral generate_series(date_trunc('month',greatest(p_from,d.valid_from))::date,date_trunc('month',least(p_to,coalesce(d.valid_to,p_to)))::date,interval '1 month') gs where d.tenant_id=p_tenant_id and d.valid_from<=p_to and (d.valid_to is null or d.valid_to>=p_from)), a as(select object_reference,sum(monthly_depreciation) depreciation_cost from m group by object_reference) select jsonb_build_object('total_depreciation_cost',coalesce(sum(depreciation_cost),0),'objects',coalesce(jsonb_agg(jsonb_build_object('object_reference',object_reference,'depreciation_cost',depreciation_cost) order by object_reference),'[]'::jsonb)) from a);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_revenue_engine_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with r as (select amount,upper(trim(coalesce(vehicle_registration,''))) vehicle from public.kpi_import_rows where tenant_id=p_tenant_id and data_kind='revenue' and is_valid and occurred_on between p_from and p_to), v as(select vehicle,sum(amount) revenue,count(*) rows from r where vehicle<>'' and vehicle<>'LASTBIL' group by vehicle) select jsonb_build_object('total_revenue',coalesce((select sum(amount) from r),0),'hired_revenue',coalesce((select sum(amount) from r where vehicle='LASTBIL'),0),'own_vehicle_revenue',coalesce((select sum(amount) from r where vehicle<>'' and vehicle<>'LASTBIL'),0),'unassigned_revenue',coalesce((select sum(amount) from r where vehicle=''),0),'vehicles',coalesce((select jsonb_agg(jsonb_build_object('vehicle',vehicle,'revenue',revenue,'rows',rows) order by vehicle) from v),'[]'::jsonb)));
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_sortyard_dashboard_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with costs as (
 select r.*,coalesce((select c.cost_category from public.kpi_cost_category_rules c where c.tenant_id=p_tenant_id and c.account=r.account and r.occurred_on>=c.valid_from and (c.valid_to is null or r.occurred_on<=c.valid_to) order by c.valid_from desc limit 1),'other') category
 from public.kpi_import_rows r where r.tenant_id=p_tenant_id and r.data_kind='cost' and r.is_valid and r.cost_center='20' and r.occurred_on between p_from and p_to
), rev as (
 select x.*,ar.project_reference rule_project,coalesce(ar.revenue_category,'unclassified') revenue_category
 from public.kpi_import_rows x join lateral(select a.* from public.kpi_workify_article_rules a where a.tenant_id=p_tenant_id and a.enabled and a.cost_center='20' and a.article_number=coalesce(x.source_data->>'Artikelnummer','') and x.occurred_on>=a.valid_from and (a.valid_to is null or x.occurred_on<=a.valid_to) order by a.valid_from desc limit 1) ar on true
 where x.tenant_id=p_tenant_id and x.data_kind='revenue' and x.is_valid and x.occurred_on between p_from and p_to
), projects as (
 select coalesce(c.project_reference,r.rule_project) project_reference,coalesce(c.cost,0) cost,coalesce(r.revenue,0) revenue
 from (select project_reference,sum(amount) cost from costs group by 1)c full join (select rule_project,sum(amount) revenue from rev group by 1)r on r.rule_project=c.project_reference
)
select jsonb_build_object('cost_center','20','name','Sortergården','from',p_from,'to',p_to,
 'revenue',coalesce((select sum(amount) from rev),0),'cost',coalesce((select sum(amount) from costs),0),
 'result',coalesce((select sum(amount) from rev),0)-coalesce((select sum(amount) from costs),0),
 'margin_percent',case when coalesce((select sum(amount) from rev),0)=0 then null else round(100*(coalesce((select sum(amount) from rev),0)-coalesce((select sum(amount) from costs),0))/nullif((select sum(amount) from rev),0),2) end,
 'projects',coalesce((select jsonb_agg(jsonb_build_object('project_reference',project_reference,'revenue',revenue,'cost',cost,'result',revenue-cost) order by project_reference) from projects),'[]'::jsonb),
 'cost_categories',coalesce((select jsonb_agg(jsonb_build_object('category',category,'amount',amount,'rows',rows) order by category) from (select category,sum(amount) amount,count(*) rows from costs group by 1)x),'[]'::jsonb),
 'revenue_categories',coalesce((select jsonb_agg(jsonb_build_object('category',revenue_category,'amount',amount,'rows',rows) order by revenue_category) from (select revenue_category,sum(amount) amount,count(*) rows from rev group by 1)x),'[]'::jsonb)));
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_workify_revenue_allocation_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')) then raise exception 'KPI access required' using errcode='42501';end if;
 return (with r as (select x.occurred_on,x.amount,case when ov.order_name is not null then case when upper(trim(x.vehicle_registration)) ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then upper(trim(x.vehicle_registration)) else '' end else upper(trim(coalesce(x.vehicle_registration,''))) end vehicle,coalesce(x.source_data->>'Artikelnummer','') article_number,coalesce(x.source_data->>'Artikelnamn',x.description,'') article_name,case when ov.order_name is not null then null else ar.project_reference end rule_project,coalesce(ar.revenue_category,'unclassified') revenue_category,case when ov.order_name is not null then 'vehicle' else coalesce(ar.target_type,'unclassified') end target_type from public.kpi_import_rows x left join lateral(select a.* from public.kpi_workify_article_rules a where a.tenant_id=p_tenant_id and a.enabled and a.article_number=coalesce(x.source_data->>'Artikelnummer','') and x.occurred_on>=a.valid_from and (a.valid_to is null or x.occurred_on<=a.valid_to) order by a.valid_from desc limit 1) ar on true   left join lateral (
   select r.order_name from private.hub_kpi_workify_order_vehicle_rules r
   where r.tenant_id=p_tenant_id and r.enabled
    and r.valid_from<=x.occurred_on and (r.valid_to is null or r.valid_to>=x.occurred_on)
    and r.order_name=lower(regexp_replace(trim(coalesce(nullif(x.project_reference,''),x.source_data->>'Littranummer','')),'\s+',' ','g'))
   order by r.valid_from desc limit 1
  ) ov on true
 where x.tenant_id=p_tenant_id and x.data_kind='revenue' and x.is_valid and x.occurred_on between p_from and p_to), a as(select *,case when target_type='project' and coalesce(trim(rule_project),'')<>'' then rule_project when target_type='vehicle' and vehicle<>'' then vehicle else 'Ej klassificerat' end economic_reference from r), c as(select revenue_category,sum(amount) revenue,count(*) rows from a group by revenue_category) select jsonb_build_object('total_revenue',coalesce((select sum(amount) from a),0),'classified_revenue',coalesce((select sum(amount) from a where economic_reference<>'Ej klassificerat'),0),'unclassified_revenue',coalesce((select sum(amount) from a where economic_reference='Ej klassificerat'),0),'categories',coalesce((select jsonb_agg(jsonb_build_object('category',revenue_category,'revenue',revenue,'rows',rows) order by revenue_category) from c),'[]'::jsonb),'project_revenue',coalesce((select sum(amount) from a where target_type='project'),0),'vehicle_revenue',coalesce((select sum(amount) from a where target_type='vehicle'),0)));
end $function$;
-- Revoke inherited anonymous execution while retaining existing authenticated and worker callers.
do $$declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p where p.pronamespace='public'::regnamespace and p.prosecdef and has_function_privilege('anon',p.oid,'EXECUTE') loop
  execute format('grant execute on function %s to authenticated,service_role',f.signature);
  execute format('revoke all on function %s from public,anon',f.signature);
 end loop;
end $$;
-- Scheduler/trigger entrypoints have no browser-facing role.
revoke all on function public.hub_transpa_daily_sync_tick_v1(boolean),public.kpi_hide_imported_project_units(),public.kpi_log_bsmart_review() from authenticated;

-- The legacy import and period writers must authorize before any mutation.
CREATE OR REPLACE FUNCTION public.hub_kpi_ingest_cost_rows_v1(p_tenant_id uuid, p_rows jsonb, p_source_system text, p_cost_center text, p_file_name text DEFAULT NULL::text, p_file_hash text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_batch uuid; v_inserted int:=0; v_skipped int:=0; v_total numeric:=0; v_min date; v_max date;
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage')) then raise exception 'KPI administrator required' using errcode='42501';end if;
 if jsonb_typeof(p_rows)<>'array' then raise exception 'p_rows must be a JSON array'; end if;
 select min((x->>'occurred_on')::date),max((x->>'occurred_on')::date),coalesce(sum((x->>'amount')::numeric),0)
 into v_min,v_max,v_total from jsonb_array_elements(p_rows) x;
 insert into public.kpi_import_batches(tenant_id,source_type,data_kind,file_name,file_type,file_hash,status,row_count,valid_row_count,invalid_row_count,period_start,period_end,column_mapping,provenance,error_summary,created_by,completed_at)
 values(p_tenant_id,case when p_source_system='NEXT' then 'hub_api' else 'manual_excel' end,'cost',p_file_name,case when p_file_name ilike '%.xlsx' then 'xlsx' else null end,p_file_hash,'processing',jsonb_array_length(p_rows),0,0,v_min,v_max,
 '{"occurred_on":"occurred_on","project_reference":"project_reference","account":"account","description":"description","amount":"amount"}'::jsonb,
 jsonb_build_object('source_system',p_source_system,'cost_center',p_cost_center),'{}'::jsonb,coalesce(p_created_by,auth.uid()),null) returning id into v_batch;

 insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,project_reference,cost_center,account,description,amount,currency,is_valid,validation_errors,source_data,source_system,external_transaction_id,source_fingerprint)
 select p_tenant_id,v_batch,ord::int,'cost',(x->>'occurred_on')::date,x->>'project_reference',p_cost_center,x->>'account',x->>'description',(x->>'amount')::numeric,coalesce(x->>'currency','SEK'),true,'{}'::jsonb,x,p_source_system,x->>'external_transaction_id',
 encode(extensions.digest(concat_ws('|',p_source_system,coalesce(x->>'external_transaction_id',''),x->>'occurred_on',x->>'project_reference',x->>'account',x->>'amount',coalesce(x->>'verification_no',''),coalesce(x->>'description','')),'sha256'),'hex')
 from jsonb_array_elements(p_rows) with ordinality a(x,ord)
 on conflict (tenant_id,data_kind,source_fingerprint) where source_fingerprint is not null do nothing;
 get diagnostics v_inserted=row_count;
 v_skipped:=jsonb_array_length(p_rows)-v_inserted;
 update public.kpi_import_batches set status=case when v_inserted=0 and jsonb_array_length(p_rows)>0 then 'needs_review' else 'completed' end,
 valid_row_count=v_inserted,invalid_row_count=0,completed_at=now(),
 provenance=provenance||jsonb_build_object('inserted_rows',v_inserted,'duplicate_rows_skipped',v_skipped,'source_total',v_total)
 where id=v_batch;
 return jsonb_build_object('batch_id',v_batch,'source_system',p_source_system,'cost_center',p_cost_center,'received_rows',jsonb_array_length(p_rows),'inserted_rows',v_inserted,'duplicate_rows_skipped',v_skipped,'source_total',v_total,'period_start',v_min,'period_end',v_max);
end $function$;
CREATE OR REPLACE FUNCTION public.hub_kpi_set_unit_period_v1(p_tenant_id uuid, p_unit_id uuid, p_valid_from date, p_payload jsonb, p_valid_to date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_actor uuid:=auth.uid(); v_old jsonb;
begin
 if coalesce(auth.role(),'')<>'service_role' and (auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage')) then raise exception 'KPI administrator required' using errcode='42501';end if;
 if p_valid_from is null then raise exception 'valid_from krävs'; end if;
 if p_valid_to is not null and p_valid_to<p_valid_from then raise exception 'valid_to före valid_from'; end if;
 if not exists(select 1 from public.kpi_units where id=p_unit_id and tenant_id=p_tenant_id) then raise exception 'Enheten saknas'; end if;
 if exists(select 1 from public.kpi_unit_periods where tenant_id=p_tenant_id and unit_id=p_unit_id and daterange(valid_from,coalesce(valid_to,'infinity'::date),'[]') && daterange(p_valid_from,coalesce(p_valid_to,'infinity'::date),'[]')) then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'valid_from',valid_from,'valid_to',valid_to,'payload',payload)),'[]'::jsonb) into v_old from public.kpi_unit_periods where tenant_id=p_tenant_id and unit_id=p_unit_id and daterange(valid_from,coalesce(valid_to,'infinity'::date),'[]') && daterange(p_valid_from,coalesce(p_valid_to,'infinity'::date),'[]');
   update public.kpi_unit_periods set valid_to=p_valid_from-1 where tenant_id=p_tenant_id and unit_id=p_unit_id and valid_from<p_valid_from and coalesce(valid_to,'infinity'::date)>=p_valid_from;
   delete from public.kpi_unit_periods where tenant_id=p_tenant_id and unit_id=p_unit_id and valid_from>=p_valid_from and valid_from<=coalesce(p_valid_to,'infinity'::date);
 end if;
 insert into public.kpi_unit_periods(tenant_id,unit_id,valid_from,valid_to,payload,created_by) values(p_tenant_id,p_unit_id,p_valid_from,p_valid_to,p_payload,v_actor) returning id into v_id;
 insert into public.kpi_unit_initial_setup_events(tenant_id,unit_id,actor,action,previous_periods,next_payload)
 values(p_tenant_id,p_unit_id,coalesce(v_actor,'00000000-0000-0000-0000-000000000000'::uuid),'retroactive_period_change',coalesce(v_old,'[]'::jsonb),jsonb_build_object('period_id',v_id,'valid_from',p_valid_from,'valid_to',p_valid_to,'payload',p_payload));
 return v_id;
end $function$;
