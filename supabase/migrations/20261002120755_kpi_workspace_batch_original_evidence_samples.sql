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
 if p_dimension not in ('all','cost_center','group','unit','vehicle','category','shared_cost') or p_reference_type not in ('project','vehicle','article','account','fact') or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 or p_page<0 then raise exception 'Ogiltigt urval';end if;
 with facts as materialized(select * from private.hub_kpi_filtered_classified_facts_v1(p_tenant_id,p_from,p_to,'{}'::jsonb)),
 rows as(
  select fact_id,occurred_on,kind,amount,project,vehicle,account,original,source,description,file_name,row_number,cost_center,business_group,unit_id::text unit_key,unit_name,category,false held from facts where case p_dimension when 'all' then true when 'cost_center' then cost_center='unclassified' when 'group' then business_group='Ej klassificerat' when 'unit' then unit_id is null when 'vehicle' then vehicle is null when 'shared_cost' then source='NEXT' and kind='cost' and project is not null else category in ('other','unclassified') end
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

