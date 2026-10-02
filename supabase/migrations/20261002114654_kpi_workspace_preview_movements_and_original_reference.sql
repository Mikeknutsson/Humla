CREATE OR REPLACE FUNCTION public.hub_kpi_match_queue_v2(p_tenant_id uuid, p_from date, p_to date, p_dimension text DEFAULT 'cost_center'::text, p_reference_type text DEFAULT 'project'::text, p_search text DEFAULT ''::text, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
AS $function$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_dimension not in ('all','cost_center','group','unit','vehicle','category','shared_cost') or p_reference_type not in ('project','vehicle','article','account','fact') or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 or p_page<0 then raise exception 'Ogiltigt urval';end if;
 with facts as materialized(select * from private.hub_kpi_classified_facts_v1(p_tenant_id,p_from,p_to)),
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
 page as(select * from grouped order by abs(amount) desc,source,kind,reference limit 100 offset p_page*100)
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('samples',coalesce((select jsonb_agg(to_jsonb(s))from(
select occurred_on,amount,project,project_name,vehicle,account,description,file_name,row_number,original from keyed k
where k.source=p.source and k.kind=p.kind and coalesce(k.reference,k.fact_id)=p.reference and (case when k.reference is null then 'fact' else p_reference_type end)=p.reference_type
order by occurred_on,k.fact_id limit 5)s),'[]')))from page p),'[]'),'total_groups',(select count(*)from grouped),'rows',(select coalesce(sum(rows),0)from grouped),'groups',(select coalesce(jsonb_agg(jsonb_build_object('name',name)order by name),'[]')from public.kpi_business_groups where tenant_id=p_tenant_id and enabled),
 'units',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name)order by name),'[]')from public.kpi_units where tenant_id=p_tenant_id and enabled and origin in ('manual','manual_builder')),
 'cost_centers',(select coalesce(jsonb_agg(to_jsonb(c)order by code),'[]')from(select cost_center code,min(cost_center_name)name from public.kpi_project_classification_periods where tenant_id=p_tenant_id group by cost_center)c),
 'history',(select coalesce(jsonb_agg(to_jsonb(h)),'[]')from(select dimension,source,kind,reference_type,reference,target,valid_from,valid_to,reason,created_at from public.kpi_dashboard_allocations where tenant_id=p_tenant_id order by created_at desc limit 50)h)) into result;
 return result;
end $function$
;
create or replace function public.hub_kpi_match_changes_v1(p_tenant_id uuid,p_changes jsonb,p_from date,p_to date,p_reason text,p_preview boolean default true)
returns jsonb language plpgsql security invoker set search_path='' set statement_timeout='60s' as $fn$
declare change jsonb; output jsonb; before_values jsonb; after_values jsonb; result jsonb; saved integer:=0;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'array' or jsonb_array_length(p_changes) not between 1 and 100 or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Kontrollera urval och datum';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':kpi-matching',0));
 if p_preview then
  with facts as materialized(select * from private.hub_kpi_classified_facts_v1(p_tenant_id,p_from,p_to)), cc as(select cost_center,sum(amount) filter(where kind='cost') cost,sum(amount) filter(where kind='revenue') revenue from facts group by cost_center), units as(select coalesce(unit_name,'Ej fördelat') name,sum(amount) filter(where kind='cost') cost,sum(amount) filter(where kind='revenue') revenue from facts group by 1)
  select jsonb_build_object('cost_centers',(select jsonb_agg(to_jsonb(c)) from cc c),'units',(select jsonb_agg(to_jsonb(u)) from units u),'cost',(select coalesce(sum(amount)filter(where kind='cost'),0)from facts),'revenue',(select coalesce(sum(amount)filter(where kind='revenue'),0)from facts)) into before_values;
 end if;
 begin
  for change in select value from jsonb_array_elements(p_changes) loop
   result:=public.hub_kpi_match_save_many_v1(p_tenant_id,jsonb_build_array(change->'item'),change->'targets',(change->>'valid_from')::date,nullif(change->>'valid_to','')::date,p_reason);
   saved:=saved+(result->>'saved')::int;
  end loop;
  if p_preview then
   with facts as materialized(select * from private.hub_kpi_classified_facts_v1(p_tenant_id,p_from,p_to)), cc as(select cost_center,sum(amount) filter(where kind='cost') cost,sum(amount) filter(where kind='revenue') revenue from facts group by cost_center), units as(select coalesce(unit_name,'Ej fördelat') name,sum(amount) filter(where kind='cost') cost,sum(amount) filter(where kind='revenue') revenue from facts group by 1)
   select jsonb_build_object('cost_centers',(select jsonb_agg(to_jsonb(c)) from cc c),'units',(select jsonb_agg(to_jsonb(u)) from units u),'cost',(select coalesce(sum(amount)filter(where kind='cost'),0)from facts),'revenue',(select coalesce(sum(amount)filter(where kind='revenue'),0)from facts)) into after_values;
   with movements as (
 select 'cost_center' dimension,coalesce(b->>'cost_center',a->>'cost_center') name,coalesce((b->>'cost')::numeric,0) before_cost,coalesce((a->>'cost')::numeric,0) after_cost,coalesce((b->>'revenue')::numeric,0) before_revenue,coalesce((a->>'revenue')::numeric,0) after_revenue
 from jsonb_array_elements(coalesce(before_values->'cost_centers','[]')) b full join jsonb_array_elements(coalesce(after_values->'cost_centers','[]')) a on b->>'cost_center'=a->>'cost_center'
 union all
 select 'unit',coalesce(b->>'name',a->>'name'),coalesce((b->>'cost')::numeric,0),coalesce((a->>'cost')::numeric,0),coalesce((b->>'revenue')::numeric,0),coalesce((a->>'revenue')::numeric,0)
 from jsonb_array_elements(coalesce(before_values->'units','[]')) b full join jsonb_array_elements(coalesce(after_values->'units','[]')) a on b->>'name'=a->>'name'
 )
 select jsonb_build_object('before',before_values,'after',after_values,'saved',saved,'preview',true,'movements',coalesce(jsonb_agg(to_jsonb(m))filter(where before_cost<>after_cost or before_revenue<>after_revenue),'[]')) into output from movements m;
   raise exception using errcode='PZ001',message='preview_rollback';
  end if;
 exception when sqlstate 'PZ001' then
  if not p_preview then raise;end if;
 end;
 return coalesce(output,jsonb_build_object('saved',saved,'preview',false));
end $fn$;
revoke all on function public.hub_kpi_match_changes_v1(uuid,jsonb,date,date,text,boolean) from public,anon;
grant execute on function public.hub_kpi_match_changes_v1(uuid,jsonb,date,date,text,boolean) to authenticated;
