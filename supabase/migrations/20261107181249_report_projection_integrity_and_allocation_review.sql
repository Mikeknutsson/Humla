-- Keep both report projections in lockstep before making a generation visible.
create or replace function private.hub_validate_report_projection_v1(p_tenant uuid, p_generation uuid)
returns void language plpgsql set search_path='' set jit=off as $$
begin
 if exists (
  with facts as materialized (
   select fact_id,fiscal_year,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center
   from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation
  ), display as materialized (
   select fact_id,fiscal_year,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center
   from private.hub_kpi_prepared_display_facts where tenant_id=p_tenant and generation_id=p_generation
  )
  select 1 from facts group by fact_id having count(*)>1
  union all select 1 from display group by fact_id having count(*)>1
  union all select 1 from facts f full join display d using(fact_id)
   where f is distinct from d
 ) then
  raise exception 'Report projection has duplicate, missing or inconsistent facts';
 end if;
end $$;
revoke all on function private.hub_validate_report_projection_v1(uuid,uuid) from public,anon,authenticated;

do $$
declare definition text:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 marker text:='update private.hub_kpi_report_generations set completed_at=';
begin
 if strpos(definition,marker)=0 then raise exception 'Report publication hook missing';end if;
 execute replace(definition,marker,
  'phase:=''projection_integrity'';phase_started:=clock_timestamp();'
  ||'perform private.hub_validate_report_projection_v1(job.tenant_id,generation);'
  ||'metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));'
  ||marker);
end $$;

create or replace function public.hub_kpi_allocation_review_v1(
 p_tenant_id uuid,p_from date,p_to date,p_page integer default 0
) returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='20s' as $$
declare generation uuid;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then
  raise exception 'KPI-administratör krävs' using errcode='42501';
 end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 or p_page is null or p_page not between 0 and 10000 then
  raise exception 'Välj ett giltigt datumintervall på högst ett år';
 end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then raise exception 'Publicerat rapportunderlag saknas';end if;
 return (
  with facts as materialized (
   select f.fact_id,f.occurred_on,f.kind,f.source,f.amount,f.project,f.vehicle,f.unit_id,f.unit_name,f.cost_center,f.description,
    f.classification_source->'probabilistic_mapping' probability,
    case when f.unit_id is null or u.data->>'report_fallback'='unresolved' or f.classification_source?'unresolved_unit'
      then 'unallocated'
      when f.classification_source#>>'{probabilistic_mapping,decision}' in ('auto_match','probable_match') then 'probable'
      else 'allocated' end allocation_state
   from private.hub_kpi_prepared_facts f
   left join public.hub_objects u on u.tenant_id=f.tenant_id and u.id=f.unit_id
   where f.tenant_id=p_tenant_id and f.generation_id=generation and f.occurred_on between p_from and p_to
    and f.kind in ('cost','revenue') and f.amount<>0
    and not coalesce(f.display_original @> '{"_humla_excluded_from_kpi":true}',false)
  ), review as materialized (
   select f.*,r.id::text raw_id,
    case when f.source='NEXT' then nullif(trim(r.project_reference),'') end reusable_project,
    (select a.target from public.kpi_dashboard_allocations a
     where a.tenant_id=p_tenant_id and a.dimension='unit' and a.source=f.source and a.kind=f.kind
      and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)
      and ((a.reference_type='fact' and a.reference=r.id::text)
       or (f.source='NEXT' and a.reference_type='project' and a.reference=r.project_reference))
     order by (a.reference_type='fact') desc,a.valid_from desc limit 1) saved_target
   from facts f left join public.kpi_import_rows r on r.tenant_id=p_tenant_id and r.id=case when f.fact_id ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then f.fact_id::uuid end
   where f.allocation_state<>'allocated'
   order by abs(f.amount) desc,f.fact_id limit 25 offset p_page*25
  ), units as (
   select k.id,k.name from public.kpi_units k
   join public.hub_objects o on o.tenant_id=k.tenant_id and o.id=k.id and o.object_type='EconomicUnit'
   where k.tenant_id=p_tenant_id and k.enabled and k.origin in ('manual','manual_builder')
    and o.status='active' and o.data->>'report_fallback' is distinct from 'unresolved'
  )
  select jsonb_build_object('generation',generation,
   'totals',(select coalesce(jsonb_agg(to_jsonb(t) order by allocation_state,kind),'[]') from (
    select allocation_state,kind,count(*) rows,sum(amount) amount from facts group by 1,2
   )t),
   'review_count',(select count(*) from facts where allocation_state<>'allocated'),
   'items',(select coalesce(jsonb_agg(to_jsonb(r) order by abs(r.amount) desc,r.fact_id),'[]') from review r),
   'units',(select coalesce(jsonb_agg(to_jsonb(u) order by u.name,u.id),'[]') from units u)
  )
 );
end $$;
revoke all on function public.hub_kpi_allocation_review_v1(uuid,date,date,integer) from public,anon;
grant execute on function public.hub_kpi_allocation_review_v1(uuid,date,date,integer) to authenticated;

create or replace function public.hub_kpi_confirm_review_unit_v1(
 p_tenant_id uuid,p_generation uuid,p_fact_id text,p_unit_id uuid,p_remember_project boolean default false
) returns jsonb language plpgsql security definer set search_path='' set statement_timeout='20s' as $$
declare f private.hub_kpi_prepared_facts;r public.kpi_import_rows;ref text;ref_type text;end_date date;result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then
  raise exception 'KPI-administratör krävs' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':kpi-matching',0));
 if not exists(select 1 from private.hub_kpi_report_state where tenant_id=p_tenant_id and active_generation=p_generation) then
  raise exception 'Rapportunderlaget har uppdaterats. Läs in kön igen.' using errcode='40001';
 end if;
 select * into f from private.hub_kpi_prepared_facts
 where tenant_id=p_tenant_id and generation_id=p_generation and fact_id=p_fact_id;
 if not found or f.source not in ('NEXT','Workify') or f.amount=0
  or coalesce(f.display_original @> '{"_humla_excluded_from_kpi":true}',false) then
  raise exception 'Posten kan inte mappas med snabbvalet';
 end if;
 select * into r from public.kpi_import_rows where tenant_id=p_tenant_id and id=case when f.fact_id ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then f.fact_id::uuid end and data_kind=f.kind;
 if not found then raise exception 'Posten saknar en entydig importrad';end if;
 if not exists(
  select 1 from public.hub_objects o cross join lateral jsonb_array_elements(o.data->'periods')p
  where o.tenant_id=p_tenant_id and o.id=p_unit_id and o.object_type='EconomicUnit' and o.status='active'
   and o.data->>'report_fallback' is distinct from 'unresolved'
   and coalesce((p.value->>'enabled')::boolean,false) and (p.value->>'valid_from')::date<=f.occurred_on
   and coalesce(nullif(p.value->>'valid_to','')::date,'infinity'::date)>=f.occurred_on
 ) or exists(select 1 from private.hub_kpi_project_exclusions where tenant_id=p_tenant_id and enabled and economic_unit_id=p_unit_id) then
  raise exception 'Enheten måste vara aktiv och ingå i rapporten på postens datum';
 end if;
 if p_remember_project then
  if f.source<>'NEXT' or nullif(trim(r.project_reference),'') is null then
   raise exception 'Återanvändning gäller poster med projektreferens från NeXT';
  end if;
  ref_type:='project';ref:=trim(r.project_reference);end_date:=null;
 else
  ref_type:='fact';ref:=r.id::text;end_date:=f.occurred_on;
 end if;
 if exists(select 1 from public.kpi_dashboard_allocations a
  where a.tenant_id=p_tenant_id and a.dimension='unit' and a.source=f.source and a.kind=f.kind
   and a.reference_type=ref_type and a.reference=ref and a.target=p_unit_id::text
   and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)
 ) then return jsonb_build_object('saved',0,'target',p_unit_id);end if;
 result:=public.hub_kpi_match_save_v1(p_tenant_id,
  jsonb_build_array(jsonb_build_object('source',f.source,'kind',f.kind,'reference_type',ref_type,'reference',ref)),
  'unit',p_unit_id::text,f.occurred_on,end_date,'Bekräftad i Humlas granskningskö');
 return result||jsonb_build_object('target',p_unit_id);
end $$;
revoke all on function public.hub_kpi_confirm_review_unit_v1(uuid,uuid,text,uuid,boolean) from public,anon;
grant execute on function public.hub_kpi_confirm_review_unit_v1(uuid,uuid,text,uuid,boolean) to authenticated;

-- Run the shared engine for a selected review row outside the nightly batch.
create or replace function public.hub_kpi_assess_review_unit_v1(
 p_tenant_id uuid,p_generation uuid,p_fact_id text
) returns jsonb language plpgsql security definer set search_path='' set statement_timeout='20s' as $$
declare assessment jsonb;assessment_run uuid;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then
  raise exception 'KPI-administratör krävs' using errcode='42501';
 end if;
 if not exists(select 1 from private.hub_kpi_report_state where tenant_id=p_tenant_id and active_generation=p_generation) then
  raise exception 'Rapportunderlaget har uppdaterats. Läs in kön igen.' using errcode='40001';
 end if;
 if not exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=p_tenant_id
  and generation_id=p_generation and fact_id=p_fact_id and kind in ('cost','revenue') and amount<>0
  and not coalesce(display_original @> '{"_humla_excluded_from_kpi":true}',false)) then
  raise exception 'Rapportposten kunde inte hittas';
 end if;
 assessment:=private.hub_match_fact_v2(p_tenant_id,p_generation,p_fact_id);
 assessment_run:=(assessment->>'run_id')::uuid;
 return jsonb_build_object('decision',assessment->>'decision','candidates',coalesce((
  select jsonb_agg(to_jsonb(c) order by c.support desc,c.unit_id) from (
   select (s.value->>'object_id')::uuid unit_id,(s.value->>'support')::numeric support,
    (select jsonb_agg(distinct e.signal_type) from public.hub_match_evidence e
     where e.tenant_id=p_tenant_id and e.run_id=assessment_run and e.candidate_object_id=(s.value->>'object_id')::uuid) signals
   from jsonb_array_elements(coalesce(assessment->'candidates','[]'))s
   order by (s.value->>'support')::numeric desc,s.value->>'object_id' limit 3
  )c
 ),'[]'));
end $$;
revoke all on function public.hub_kpi_assess_review_unit_v1(uuid,uuid,text) from public,anon;
grant execute on function public.hub_kpi_assess_review_unit_v1(uuid,uuid,text) to authenticated;
