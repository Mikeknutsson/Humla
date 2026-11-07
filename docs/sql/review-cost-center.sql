-- A missing department can be resolved on the review row without changing the amount.
create or replace function public.hub_kpi_confirm_review_mapping_v1(
 p_tenant_id uuid,p_generation uuid,p_fact_id text,p_unit_id uuid,p_remember_project boolean,p_cost_center text
) returns jsonb language plpgsql security definer set search_path='' set statement_timeout='20s' as $$
declare f private.hub_kpi_prepared_facts;unit_result jsonb;center_result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then
  raise exception 'KPI-administratör krävs' using errcode='42501';
 end if;
 if p_unit_id is null and p_cost_center is null then raise exception 'Välj enhet eller kostnadsställe';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':kpi-matching',0));
 if not exists(select 1 from private.hub_kpi_report_state where tenant_id=p_tenant_id and active_generation=p_generation) then
  raise exception 'Rapportunderlaget har uppdaterats. Läs in kön igen.' using errcode='40001';
 end if;
 if p_unit_id is not null then
  unit_result:=public.hub_kpi_confirm_review_unit_v1(p_tenant_id,p_generation,p_fact_id,p_unit_id,p_remember_project);
 end if;
 if p_cost_center is not null then
  select * into f from private.hub_kpi_prepared_facts
   where tenant_id=p_tenant_id and generation_id=p_generation and fact_id=p_fact_id;
  if not found or f.source not in ('NEXT','Workify') or f.kind not in ('cost','revenue') or f.amount=0
   or coalesce(f.display_original @> '{"_humla_excluded_from_kpi":true}',false)
   or coalesce(nullif(f.cost_center,''),'unclassified')<>'unclassified'
   or not exists(select 1 from public.kpi_import_rows r where r.tenant_id=p_tenant_id and r.data_kind=f.kind
    and r.id=case when p_fact_id ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then p_fact_id::uuid end) then
   raise exception 'Välj en ofördelad importrad för att sätta kostnadsställe';
  end if;
  if p_cost_center !~ '^[0-9]{2}$' then raise exception 'Välj ett registrerat kostnadsställe';end if;
  if not exists(select 1 from public.kpi_dashboard_allocations a
   where a.tenant_id=p_tenant_id and a.dimension='cost_center' and a.source=f.source and a.kind=f.kind
    and a.reference_type='fact' and a.reference=p_fact_id and a.target=p_cost_center
    and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)) then
   center_result:=public.hub_kpi_match_save_v1(p_tenant_id,
    jsonb_build_array(jsonb_build_object('source',f.source,'kind',f.kind,'reference_type','fact','reference',p_fact_id)),
    'cost_center',p_cost_center,f.occurred_on,f.occurred_on,'Kostnadsställe bekräftat i Humlas granskningskö');
  end if;
 end if;
 return jsonb_build_object('saved',coalesce((unit_result->>'saved')::integer,0)+coalesce((center_result->>'saved')::integer,0),
  'target',p_unit_id,'cost_center',p_cost_center);
end $$;
revoke all on function public.hub_kpi_confirm_review_mapping_v1(uuid,uuid,text,uuid,boolean,text) from public,anon;
grant execute on function public.hub_kpi_confirm_review_mapping_v1(uuid,uuid,text,uuid,boolean,text) to authenticated;

do $$
declare definition text:=pg_get_functiondef('public.hub_kpi_allocation_review_v1(uuid,date,date,integer)'::regprocedure);
begin
 if strpos(definition,'limit 1) saved_target')=0 then raise exception 'Review projection hook missing';end if;
 definition:=replace(definition,'limit 1) saved_target', $new$limit 1) saved_target,
    (select a.target from public.kpi_dashboard_allocations a
     where a.tenant_id=p_tenant_id and a.dimension='cost_center' and a.source=f.source and a.kind=f.kind
      and a.reference_type='fact' and a.reference=r.id::text
      and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)
     order by a.valid_from desc limit 1) saved_cost_center$new$);
 definition:=replace(definition,'f.allocation_state<>''allocated''',
  '(f.allocation_state<>''allocated'' or coalesce(nullif(f.cost_center,''''),''unclassified'')=''unclassified'')');
 definition:=replace(definition,'from facts where allocation_state<>''allocated''',
  'from facts f where (f.allocation_state<>''allocated'' or coalesce(nullif(f.cost_center,''''),''unclassified'')=''unclassified'')');
 definition:=replace(definition,'''review_count'',', $new$
   'cost_centers',(select coalesce(jsonb_agg(to_jsonb(c) order by c.code),'[]') from (
    select cost_center code,max(cost_center_name) name from public.kpi_project_classification_periods
    where tenant_id=p_tenant_id and cost_center ~ '^[0-9]{2}$' group by cost_center
   ) c),
   'unclassified_center_count',(select count(*) from facts where coalesce(nullif(cost_center,''),'unclassified')='unclassified'),
   'review_count',$new$);
 execute definition;
end $$;
