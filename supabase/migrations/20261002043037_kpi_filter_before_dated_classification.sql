-- Filter immutable economic fields and selected months before dated classification.
-- Financial calculation, classification rules and source data are unchanged.
CREATE OR REPLACE FUNCTION private.hub_kpi_filtered_classified_facts_v1(p_tenant_id uuid, p_from date, p_to date, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb, cost_center text, cost_center_name text, classification_source jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with facts as materialized(
 select f.* from private.hub_kpi_financial_facts_v1(p_tenant_id,p_from,p_to) f
 where auth.uid() is not null and public.hub_has_permission(p_tenant_id,'kpi.read')
 and (not(p_filters?'_selected_months') or extract(month from f.occurred_on)::int in (select value::int from jsonb_array_elements_text(p_filters->'_selected_months')))
 and (not(p_filters?'unit') or coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=p_filters->>'unit')
 and (not(p_filters?'vehicle') or coalesce(f.vehicle,'unassigned')=p_filters->>'vehicle')
 and (not(p_filters?'project') or coalesce(f.project,'unassigned')=p_filters->>'project')
 and (not(p_filters?'category') or f.category=p_filters->>'category')
 and (not(p_filters?'kind') or f.kind=p_filters->>'kind')
 and (not(p_filters?'source') or f.source=p_filters->>'source')
 and (not(p_filters?'date_from') or f.occurred_on>=(p_filters->>'date_from')::date)
 and (not(p_filters?'date_to') or f.occurred_on<=(p_filters->>'date_to')::date)
 ),
 center_names as materialized(select cost_center,min(cost_center_name) name from public.kpi_project_classification_periods where tenant_id=p_tenant_id group by cost_center),
 registry as materialized(select * from public.kpi_project_classification_periods where tenant_id=p_tenant_id and valid_from<=p_to and (valid_to is null or valid_to>=p_from))
 select f.fact_id,f.occurred_on,f.kind,f.amount,f.category,f.project,f.vehicle,f.unit_id,f.unit_name,
  case when f.original#>>'{_humla_distribution,status}' in ('allocated','no_eligible_units') then f.business_group when nullif(f.original#>>'{_humla_assignment,group}','') is not null then f.business_group when own_group.has_group then f.business_group when explicit_group.has_group then f.business_group
   when cc.center_count>1 or bg.group_count>1 then 'Ej klassificerat' else coalesce(bg.group_name,f.business_group) end,
  f.source,f.description,f.account,f.file_name,f.row_number,f.original,
  coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),article.cost_center,nullif(f.original->>'_humla_cost_center',''),case when cc.center_count=1 then cc.code else 'unclassified' end),
  case when coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),nullif(f.original->>'_humla_cost_center','')) is not null then coalesce((select r.name from center_names r where r.cost_center=coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),f.original->>'_humla_cost_center')),f.original->>'_humla_cost_center') when article.cost_center is not null then coalesce((select r.name from center_names r where r.cost_center=article.cost_center),article.cost_center) when cc.center_count=1 then cc.name else 'Ej klassificerat' end,
  jsonb_build_object('registry_sources',cc.sources,'article_rule_id',article.id,'manual_assignment',f.original->'_humla_assignment','reason',case when f.original#>>'{_humla_assignment,cost_center}' is not null then 'manual_dated_assignment' when f.original->>'_humla_cost_center' is not null then 'verified_import_cost_center' when article.cost_center is not null then 'exact_dated_article_rule' when cc.center_count>1 then 'conflicting_cost_centers' when cc.center_count=0 then 'missing_cost_center' else 'exact_dated_reference' end)
 from facts f
 -- A verified dated article rule classifies revenue even without a vehicle/project.
 -- Vehicle identity and group matching retain their existing dated rules.
 left join lateral(
  select a.id,nullif(trim(a.cost_center),'') cost_center
  from public.kpi_workify_article_rules a
  where f.source='Workify' and a.tenant_id=p_tenant_id and a.enabled
   and a.article_number=coalesce(f.original->>'Artikelnummer','')
   and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)
  order by a.valid_from desc,a.id limit 1
 ) article on true
 left join lateral(
  select count(distinct r.cost_center) center_count,min(r.cost_center) code,min(r.cost_center_name) name,jsonb_agg(distinct r.source) sources
  from registry r where r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
  and (r.project_reference=f.project or f.vehicle=any(r.registrations) or (f.source='TransPA' and r.project_reference=f.original->>'employee_id'))
 ) cc on true
 left join lateral(
  with candidates as(select r.business_group,case when r.project_reference=f.project then 1 when f.vehicle=any(r.registrations) then 2 else 3 end priority
   from registry r where r.business_group is not null and r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
   and (r.project_reference=f.project or f.vehicle=any(r.registrations) or (f.source='TransPA' and r.project_reference=f.original->>'employee_id')))
  select count(distinct business_group) group_count,case when count(distinct business_group)=1 then min(business_group) end group_name from candidates where priority=(select min(priority) from candidates)
 ) bg on true
 left join lateral(select exists(select 1 from public.kpi_unit_periods p where p.tenant_id=p_tenant_id and p.unit_id=f.unit_id and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on) and nullif(p.payload->>'business_group_id','') is not null) has_group) own_group on true
 left join lateral(select exists(select 1 from public.kpi_project_business_groups p where p.tenant_id=p_tenant_id and p.project_reference=f.project and p.source='kpi_admin_dated' and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)) has_group) explicit_group on true;
$function$;
revoke all on function private.hub_kpi_filtered_classified_facts_v1(uuid,date,date,jsonb) from public,anon;
grant execute on function private.hub_kpi_filtered_classified_facts_v1(uuid,date,date,jsonb) to authenticated;
CREATE OR REPLACE FUNCTION private.hub_kpi_month_facts_v1(p_tenant_id uuid, p_year integer, p_months integer[], p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb, cost_center text, cost_center_name text, classification_source jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
 perform private.hub_kpi_month_scope_v1(p_year,p_months);
 return query select f.* from private.hub_kpi_filtered_classified_facts_v1(p_tenant_id,make_date(p_year,9,1),make_date(p_year+1,8,31),p_filters||jsonb_build_object('_selected_months',to_jsonb(p_months))) f
 where extract(month from f.occurred_on)::int=any(p_months)
 and (not(p_filters?'cost_center') or f.cost_center=p_filters->>'cost_center')
 and (not(p_filters?'group') or f.business_group=p_filters->>'group')
 and (not(p_filters?'unit') or coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=p_filters->>'unit')
 and (not(p_filters?'vehicle') or coalesce(f.vehicle,'unassigned')=p_filters->>'vehicle')
 and (not(p_filters?'project') or coalesce(f.project,'unassigned')=p_filters->>'project')
 and (not(p_filters?'category') or f.category=p_filters->>'category')
 and (not(p_filters?'kind') or f.kind=p_filters->>'kind')
 and (not(p_filters?'source') or f.source=p_filters->>'source')
 and (not(p_filters?'date_from') or f.occurred_on>=(p_filters->>'date_from')::date)
 and (not(p_filters?'date_to') or f.occurred_on<=(p_filters->>'date_to')::date);
end $function$;
notify pgrst,'reload schema';
