CREATE OR REPLACE FUNCTION private.hub_kpi_classify_perf_candidate_v1(p_tenant_id uuid, p_from date, p_to date, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb, cost_center text, cost_center_name text, classification_source jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 return query execute $query$ with facts as materialized(
 select f.* from private.hub_kpi_financial_facts_v1($1,$2,$3) f
 where auth.uid() is not null and public.hub_has_permission($1,'kpi.read')
 and (not($4?'_selected_months') or extract(month from f.occurred_on)::int in (select value::int from jsonb_array_elements_text($4->'_selected_months')))
 and (not($4?'unit') or coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=$4->>'unit')
 and (not($4?'vehicle') or coalesce(f.vehicle,'unassigned')=$4->>'vehicle')
 and (not($4?'project') or coalesce(f.project,'unassigned')=$4->>'project')
 and (not($4?'category') or f.category=$4->>'category')
 and (not($4?'kind') or f.kind=$4->>'kind')
 and (not($4?'source') or f.source=$4->>'source')
 and (not($4?'date_from') or f.occurred_on>=($4->>'date_from')::date)
 and (not($4?'date_to') or f.occurred_on<=($4->>'date_to')::date)
 ),
 center_names as materialized(select cost_center,min(cost_center_name) name from public.kpi_project_classification_periods where tenant_id=$1 group by cost_center),
 registry as materialized(select * from public.kpi_project_classification_periods where tenant_id=$1 and valid_from<=$3 and (valid_to is null or valid_to>=$2)),
 registry_vehicles as materialized(select r.id,registration from registry r cross join lateral unnest(r.registrations) registration),
 registry_matches as materialized(
 select f.fact_id,r.*,case when r.project_reference=f.project then 1 when f.vehicle=any(r.registrations) then 2 else 3 end priority
 from facts f join registry r on r.project_reference=f.project and r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
 union
 select f.fact_id,r.*,case when r.project_reference=f.project then 1 when f.vehicle=any(r.registrations) then 2 else 3 end priority
 from facts f join registry_vehicles v on v.registration=f.vehicle join registry r on r.id=v.id and r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
 union
 select f.fact_id,r.*,case when r.project_reference=f.project then 1 when f.vehicle=any(r.registrations) then 2 else 3 end priority
 from facts f join registry r on f.source='TransPA' and r.project_reference=f.original->>'employee_id' and r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
 ),
 centers as materialized(select fact_id,count(distinct cost_center) center_count,min(cost_center) code,min(cost_center_name) name,jsonb_agg(distinct source) sources from registry_matches group by fact_id),
 group_priorities as(select fact_id,min(priority) priority from registry_matches where business_group is not null group by fact_id),
 groups as materialized(select r.fact_id,count(distinct r.business_group) group_count,case when count(distinct r.business_group)=1 then min(r.business_group) end group_name from registry_matches r join group_priorities p on p.fact_id=r.fact_id and p.priority=r.priority where r.business_group is not null group by r.fact_id)
 select f.fact_id,f.occurred_on,f.kind,f.amount,f.category,f.project,f.vehicle,f.unit_id,f.unit_name,
  case when f.original#>>'{_humla_distribution,status}' in ('allocated','no_eligible_units') then f.business_group when nullif(f.original#>>'{_humla_assignment,group}','') is not null then f.business_group when own_group.has_group then f.business_group when explicit_group.has_group then f.business_group
   when cc.center_count>1 or bg.group_count>1 then 'Ej klassificerat' else coalesce(bg.group_name,f.business_group) end,
  f.source,f.description,f.account,f.file_name,f.row_number,f.original,
  coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),article.cost_center,nullif(f.original->>'_humla_cost_center',''),case when cc.center_count=1 then cc.code else 'unclassified' end),
  case when coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),nullif(f.original->>'_humla_cost_center','')) is not null then coalesce((select r.name from center_names r where r.cost_center=coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),f.original->>'_humla_cost_center')),f.original->>'_humla_cost_center') when article.cost_center is not null then coalesce((select r.name from center_names r where r.cost_center=article.cost_center),article.cost_center) when cc.center_count=1 then cc.name else 'Ej klassificerat' end,
  jsonb_build_object('registry_sources',cc.sources,'article_rule_id',article.id,'manual_assignment',f.original->'_humla_assignment','reason',case when f.original#>>'{_humla_assignment,cost_center}' is not null then 'manual_dated_assignment' when f.original->>'_humla_cost_center' is not null then 'verified_import_cost_center' when article.cost_center is not null then 'exact_dated_article_rule' when cc.center_count>1 then 'conflicting_cost_centers' when coalesce(cc.center_count,0)=0 then 'missing_cost_center' else 'exact_dated_reference' end)
 from facts f
 -- A verified dated article rule classifies revenue even without a vehicle/project.
 -- Vehicle identity and group matching retain their existing dated rules.
 left join lateral(
  select a.id,nullif(trim(a.cost_center),'') cost_center
  from public.kpi_workify_article_rules a
  where f.source='Workify' and a.tenant_id=$1 and a.enabled
   and a.article_number=coalesce(f.original->>'Artikelnummer','')
   and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)
  order by a.valid_from desc,a.id limit 1
 ) article on true
 left join centers cc on cc.fact_id=f.fact_id
 left join groups bg on bg.fact_id=f.fact_id
 left join lateral(select exists(select 1 from public.kpi_unit_periods p where p.tenant_id=$1 and p.unit_id=f.unit_id and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on) and nullif(p.payload->>'business_group_id','') is not null) has_group) own_group on true
 left join lateral(select exists(select 1 from public.kpi_project_business_groups p where p.tenant_id=$1 and p.project_reference=f.project and p.source='kpi_admin_dated' and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)) has_group) explicit_group on true;$query$ using p_tenant_id,p_from,p_to,p_filters;
end
$function$;

