-- Hub reconciliation: source subtotals and missing-project evidence, without guessing identities.
-- Diagnostics are separate from the financial total and scoped explicitly in consumers.
-- Internal Workify costs to the recipient project; user-confirmed account 4600 covers booked costs.
CREATE OR REPLACE FUNCTION private.hub_kpi_project_report_v5(p_tenant_id uuid, p_from date, p_to date, p_center text DEFAULT NULL::text, p_manager text DEFAULT NULL::text, p_project uuid DEFAULT NULL::uuid, p_page integer DEFAULT 0, p_kind text DEFAULT NULL::text, p_groups text[] DEFAULT NULL::text[], p_months integer[] DEFAULT NULL::integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET plan_cache_mode TO 'force_custom_plan'
 SET work_mem TO '32MB'
AS $function$
declare answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'Not authorized' using errcode='42501';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>1096 or p_page<0 or p_page>10000 or (p_center is not null and p_center not in ('10','20','30','40','50','60','90')) or (p_kind is not null and p_kind not in ('revenue','cost')) or cardinality(p_groups)>50 or array_position(p_groups,null) is not null or cardinality(p_months)=0 or cardinality(p_months)>12 or array_position(p_months,null) is not null or exists(select 1 from unnest(p_months) m where m<1 or m>12) then raise exception 'Invalid project selection';end if;
 with registry as materialized(
  select r.project_number,r.project_name,r.project_manager,c.cost_center,c.business_group,k.object_id
  from public.kpi_next_project_register r
  join lateral(select x.cost_center,x.business_group from public.kpi_project_classification_periods x
   where x.tenant_id=p_tenant_id and x.project_reference=r.project_number and x.valid_from<=current_date and (x.valid_to is null or x.valid_to>=current_date)
   order by x.valid_from desc limit 1)c on c.cost_center in ('10','20','30','40','50','60','90')
  join lateral(select public.hub_resolve_canonical_object_v1(p_tenant_id,min(k.object_id::text)::uuid) object_id from public.hub_identity_keys k
   where k.tenant_id=p_tenant_id and k.identity_type='next_project_number' and k.identity_value=r.project_number and k.confidence=1
   having count(distinct public.hub_resolve_canonical_object_v1(k.tenant_id,k.object_id))=1)k on k.object_id is not null
  where r.tenant_id=p_tenant_id
 ), scoped as materialized(
  select * from registry where (p_center is null or cost_center=p_center) and (p_manager is null or project_manager=p_manager)
 ), selected as materialized(
  select * from scoped where (p_project is null or object_id=p_project) and (coalesce(cardinality(p_groups),0)=0 or coalesce(nullif(business_group,''),'Ingen grupp')=any(p_groups))
 ), next_all_evidence as materialized(
  select r.id::text id,r.occurred_on date,r.data_kind kind,r.amount,r.account,r.description,r.project_reference project_number,s.object_id,
   b.file_name,r.row_number,r.validation_errors,'NeXT'::text source,
   case when (r.data_kind='cost' and r.account='4600') or private.hub_workify_customer_is_internal_v1(coalesce(nullif(r.source_data->>'Kundnamn',''),nullif(r.source_data->>'Leverantör',''),'')) then true else false end internal,
   case when cr.n=1 then cr.category when coalesce(r.source_data->>'Kontobeskrivning','') ~* '^löner? ' then 'personnel' else 'unclassified' end category
  from public.kpi_import_rows r join scoped s on s.project_number=trim(r.project_reference)
  join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=p_tenant_id
  left join lateral(select count(distinct x.cost_category) n,min(x.cost_category) category from public.kpi_cost_category_rules x where x.tenant_id=p_tenant_id and x.account=r.account and x.valid_from<=r.occurred_on and (x.valid_to is null or x.valid_to>=r.occurred_on))cr on true
  where r.tenant_id=p_tenant_id and r.source_data?'Projektnr' and r.source_data?'Bokf datum' and r.data_kind in ('revenue','cost')
   and r.occurred_on between p_from and p_to and (p_months is null or extract(month from r.occurred_on)::integer=any(p_months)) and r.amount is not null and not coalesce(b.provenance,'{}'::jsonb)?'withdrawal'
   and not(s.cost_center in ('20','30') and r.data_kind='revenue')
   and not(s.cost_center='30' and r.data_kind='cost' and coalesce(r.source_data->>'Kontobeskrivning','') ~* '^(löner? |pensionsförsäkringspremier|arbetsgivaravgifter|sociala avgifter)')
   and (r.is_valid or r.validation_errors <@ '["Kostnadsfördelning behöver granskas","Fordonsbeteckning saknar verifierad regnummerkoppling"]'::jsonb)
 ), next_evidence as materialized(
  select e.* from next_all_evidence e join selected s on s.object_id=e.object_id
 ), hub_facts as materialized(
  select f.fact_id,f.occurred_on,f.kind,f.amount,f.category,f.project,f.vehicle,f.source,f.cost_center,
   case when f.source='TransPA' then jsonb_build_object('time_report_id',f.original->'time_report_id')
    else jsonb_build_object('Ordernummer',f.original->'Ordernummer','Artikelnamn',f.original->'Artikelnamn','Kundnamn',f.original->'Kundnamn') end original
  from private.hub_kpi_prepared_facts f
  join private.hub_kpi_report_state state on state.tenant_id=p_tenant_id and state.active_generation=f.generation_id
  where f.tenant_id=p_tenant_id and f.occurred_on between p_from and p_to and (p_months is null or extract(month from f.occurred_on)::integer=any(p_months)) and exists(select 1 from scoped scope where scope.cost_center=f.cost_center)
   and ((f.source='TransPA' and f.kind='cost' and f.cost_center='30') or
    (f.source='Workify' and f.original ?& array['Ordernummer','Artikelnummer','Artikeldatum','Summa','Fakturerad'] and f.kind='revenue' and f.cost_center in ('20','30') and not private.hub_workify_customer_is_internal_v1(coalesce(f.original->>'Kundnamn',''))))
 ), hub_refs as materialized(
  select distinct case when nullif(trim(project),'') is not null then 'project' else 'vehicle' end kind,
   coalesce(nullif(trim(project),''),vehicle) value from hub_facts
 ), hub_ids as materialized(
  select refs.kind,refs.value,identity.object_id from hub_refs refs
  join lateral(
   select public.hub_resolve_canonical_object_v1(p_tenant_id,min(k.object_id::text)::uuid) object_id
   from public.hub_identity_keys k where k.tenant_id=p_tenant_id and k.confidence=1 and k.identity_value=refs.value
    and ((refs.kind='project' and k.identity_type='next_project_number') or
     (refs.kind='vehicle' and k.identity_type in ('registration_number','vehicle_registration')))
   having count(distinct public.hub_resolve_canonical_object_v1(p_tenant_id,k.object_id))=1
  ) identity on identity.object_id is not null
  where (select count(*) from registry x where x.object_id=identity.object_id)=1
 ), hub_all_evidence as materialized(
  select f.source||':'||f.fact_id id,f.occurred_on date,f.kind,round(f.amount,2) amount,null::text account,
   case when f.source='TransPA' then 'TransPA tid '||coalesce(f.original->>'time_report_id','')||' · beräknad personalkostnad'
    else concat_ws(' · ',f.original->>'Ordernummer',f.original->>'Artikelnamn',f.original->>'Kundnamn') end description,
   s.project_number,s.object_id,coalesce(b.file_name,f.source||' API / Hub') file_name,r.row_number,
   '[]'::jsonb validation_errors,f.source,false internal,case when f.source='TransPA' then 'personnel' else f.category end category
  from hub_facts f
  join hub_ids identity on identity.kind=case when nullif(trim(f.project),'') is not null then 'project' else 'vehicle' end
   and identity.value=coalesce(nullif(trim(f.project),''),f.vehicle)
  join scoped s on s.object_id=identity.object_id and s.cost_center=f.cost_center
  left join public.kpi_import_rows r on r.tenant_id=p_tenant_id and r.id=case when f.fact_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then f.fact_id::uuid end
  left join public.kpi_import_batches b on b.tenant_id=p_tenant_id and b.id=r.batch_id
 ), hub_evidence as materialized(
  select e.* from hub_all_evidence e join selected s on s.object_id=e.object_id
 ), internal_payload as materialized(
  select payload from generate_series(p_from::timestamp,p_to::timestamp,interval '365 days') chunk(day)
  cross join lateral jsonb_array_elements(public.hub_kpi_internal_transfers_v1(p_tenant_id,chunk.day::date,least(chunk.day::date+364,p_to),null)->'rows') payload
 ), internal_base as materialized(
  select payload,r.id::text row_id,r.occurred_on date,round(r.amount,2) original_amount,b.file_name,r.row_number,
   coalesce((payload->>'invoiced')::boolean,false) and (payload->>'duplicate_count')::integer=1 and r.amount is not null
   and (r.is_valid or r.validation_errors <@ '["Fordonsbeteckning saknar verifierad regnummerkoppling","Workify-artikeln ska till fordon: registreringsnummer behöver mappas"]'::jsonb) eligible
  from internal_payload i join public.kpi_import_rows r on r.tenant_id=p_tenant_id and r.id=(i.payload->>'row_id')::uuid
  join public.kpi_import_batches b on b.tenant_id=p_tenant_id and b.id=r.batch_id
  where p_months is null or extract(month from r.occurred_on)::integer=any(p_months)
 ), internal_candidates as materialized(
  select i.*,s.object_id,s.project_number from internal_base i join selected s on s.project_number=i.payload->>'project'
 ), booked_internal as materialized(
  select n.object_id,sum(n.amount) amount from next_evidence n where n.kind='cost' and n.account='4600' group by n.object_id
 ), internal_totals as materialized(
  select s.object_id,coalesce(sum(c.original_amount) filter(where c.eligible),0) original,
   coalesce(max(booked.amount),0) booked_4600,
   count(c.row_id) filter(where c.eligible) rows,count(c.row_id) filter(where not c.eligible) pending_rows
  from selected s left join internal_candidates c on c.object_id=s.object_id left join booked_internal booked on booked.object_id=s.object_id group by s.object_id
 ), internal_bridge as materialized(
  select t.*,case when original>0 then greatest(original-greatest(booked_4600,0),0)
   when original<0 then least(original-least(booked_4600,0),0) else 0 end added from internal_totals t
 ), internal_scaled as materialized(
  select c.*,bridge.original,bridge.added,round(c.original_amount*case when bridge.original=0 then 0 else bridge.added/bridge.original end,2) scaled,
   row_number() over(partition by c.object_id order by c.date,c.row_id) ordinal
  from internal_candidates c join internal_bridge bridge on bridge.object_id=c.object_id where c.eligible
 ), internal_allocated as materialized(
  select c.*,scaled+case when ordinal=1 then added-sum(scaled) over(partition by object_id) else 0 end charged from internal_scaled c
 ), internal_evidence as materialized(
  select 'workify-internal:'||row_id id,date,'cost'::text kind,charged amount,null::text account,
   'Intern Workify · order '||coalesce(payload->>'order','')||' · '||coalesce(payload->>'description','')||
    ' · ursprungligt belopp '||original_amount::text||' kr; kostnad efter avräkning mot 4600' description,
   project_number,object_id,file_name,row_number,'[]'::jsonb validation_errors,'Workify intern'::text source,true internal,
   coalesce(payload->>'category','unclassified') category from internal_allocated
 ), internal_income as materialized(
  select 'workify-internal-income:'||i.row_id id,i.date,'revenue'::text kind,i.original_amount amount,null::text account,
   'Intern Workify · order '||coalesce(i.payload->>'order','')||' · mottagande projekt '||coalesce(i.payload->>'project','') description,
   s.project_number,s.object_id,i.file_name,i.row_number,'[]'::jsonb validation_errors,'Workify intern'::text source,true internal,
   coalesce(i.payload->>'category','unclassified') category
  from internal_base i join selected s on s.object_id=public.hub_resolve_canonical_object_v1(p_tenant_id,(i.payload->>'carrier_id')::uuid)
   and s.cost_center=i.payload->>'source_center'
  where i.eligible and i.payload->>'category' in ('transport','material','tipp_deponi')
   and (select count(*) from registry x where x.object_id=s.object_id)=1
   and s.object_id is distinct from (select x.object_id from registry x where x.project_number=i.payload->>'project')
 ), option_evidence as materialized(
  select object_id,kind,amount from next_all_evidence
  union all select object_id,kind,amount from hub_all_evidence
  union all select s.object_id,'cost',i.original_amount from internal_base i join scoped s on s.project_number=i.payload->>'project' where i.eligible
  union all select s.object_id,'revenue',i.original_amount from internal_base i join scoped s
   on s.object_id=public.hub_resolve_canonical_object_v1(p_tenant_id,(i.payload->>'carrier_id')::uuid) and s.cost_center=i.payload->>'source_center'
   where i.eligible and i.payload->>'category' in ('transport','material','tipp_deponi')
    and (select count(*) from registry x where x.object_id=s.object_id)=1
    and s.object_id is distinct from (select x.object_id from registry x where x.project_number=i.payload->>'project')
 ), option_totals as(
  select object_id,coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost from option_evidence group by object_id
 ), available_groups as(
  select distinct coalesce(nullif(s.business_group,''),'Ingen grupp') name from scoped s join option_totals t on t.object_id=s.object_id where t.revenue<>0 or t.cost<>0
 ), evidence as materialized(select * from next_evidence union all select * from hub_evidence union all select * from internal_evidence union all select * from internal_income), rollup as (
  select s.object_id id,s.project_number,s.project_name,s.cost_center,s.project_manager,s.business_group,count(e.id) rows,
   round(coalesce(sum(e.amount) filter(where e.kind='revenue' and not e.internal),0),2) external_revenue,
   round(coalesce(sum(e.amount) filter(where e.kind='revenue' and e.internal),0),2) internal_revenue,
   round(coalesce(sum(e.amount) filter(where e.kind='cost' and not e.internal),0),2) external_cost,
   round(coalesce(sum(e.amount) filter(where e.kind='cost' and e.internal),0),2) internal_cost,
   round(coalesce(sum(e.amount) filter(where e.kind='revenue'),0),2) revenue,
   round(coalesce(sum(e.amount) filter(where e.kind='cost'),0),2) cost,
   round(coalesce(sum(e.amount) filter(where e.kind='revenue'),0)-coalesce(sum(e.amount) filter(where e.kind='cost'),0),2) result,
   case when sum(e.amount) filter(where e.kind='revenue')>0 then round(100*(sum(e.amount) filter(where e.kind='revenue')-coalesce(sum(e.amount) filter(where e.kind='cost'),0))/(sum(e.amount) filter(where e.kind='revenue')),2) end margin,
   round(coalesce(sum(e.amount) filter(where e.kind='cost' and e.category='personnel'),0),2) personnel,
   count(e.id) filter(where e.kind='cost' and e.category='unclassified') unclassified_rows,
   count(e.id) filter(where e.validation_errors<>'[]'::jsonb) vehicle_allocation_pending
  from selected s left join evidence e on e.object_id=s.object_id group by s.object_id,s.project_number,s.project_name,s.cost_center,s.project_manager,s.business_group
 ), monthly as(
  select date_trunc('month',e.date)::date as month_start,round(coalesce(sum(e.amount) filter(where e.kind='revenue'),0),2) revenue,
   round(coalesce(sum(e.amount) filter(where e.kind='cost'),0),2) cost,
   round(coalesce(sum(e.amount) filter(where e.kind='revenue'),0)-coalesce(sum(e.amount) filter(where e.kind='cost'),0),2) result
  from evidence e group by 1
 ), source_totals as(
  select source,kind,count(*) rows,round(sum(amount),2) amount from evidence group by source,kind
 ), next_unassigned as materialized(
  select trim(r.project_reference) project_number,r.data_kind kind,r.amount
  from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=p_tenant_id
  where r.tenant_id=p_tenant_id and r.source_data?'Projektnr' and r.source_data?'Bokf datum'
   and r.data_kind in ('cost','revenue') and r.occurred_on between p_from and p_to
   and (p_months is null or extract(month from r.occurred_on)::integer=any(p_months))
   and not coalesce(b.provenance,'{}'::jsonb)?'withdrawal'
   and not exists(select 1 from registry s where s.project_number=trim(r.project_reference))
 ), unassigned_projects as(
  select project_number,count(*) rows,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,
   round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue from next_unassigned group by project_number
 ), unmapped_hub as(
  select f.* from hub_facts f where not exists(select 1 from hub_all_evidence e where e.id=f.source||':'||f.fact_id)
 ), totals as(
  select round(coalesce(sum(revenue),0),2) revenue,round(coalesce(sum(cost),0),2) cost,round(coalesce(sum(result),0),2) result,
   case when sum(revenue)>0 then round(100*sum(result)/sum(revenue),2) end margin,
   round(coalesce(sum(personnel),0),2) personnel,round(coalesce(sum(internal_revenue),0),2) internal_revenue,
   round(coalesce(sum(internal_cost),0),2) internal_cost,round(coalesce(sum(external_revenue),0),2) external_revenue,
   round(coalesce(sum(external_cost),0),2) external_cost,sum(rows) rows,sum(vehicle_allocation_pending) vehicle_allocation_pending,sum(unclassified_rows) unclassified_rows
  from rollup
 ), details as(
  select * from evidence where p_project is not null and (p_kind is null or kind=p_kind) order by date desc,id limit 200 offset p_page*200
 )
 select jsonb_build_object('from',p_from,'to',p_to,'source','NeXT projektbokföring; Workify externa intäkter för KST 20/30; TransPA personalkostnad för KST 30','salary_source','NeXT för övriga KST; Transport KST 30 använder befintlig beräknad personalkostnad från TransPA API',
  'scope','Uppdelning enligt senaste bekräftade projektregister. Belopp exklusive moms från importerade NeXT-poster och Hub-underlag. TransPA-personal för Transport är beräknad från rapporterad tid. Ingen slutprognos.',
  'internal_workify',jsonb_build_object('original',coalesce((select sum(original) from internal_bridge),0),
   'booked_4600',coalesce((select sum(booked_4600) from internal_bridge),0),
   'covered_4600',coalesce((select sum(original-added) from internal_bridge),0),'added',coalesce((select sum(added) from internal_bridge),0),
   'income',coalesce((select sum(amount) from internal_income),0),'income_rows',(select count(*) from internal_income),'rows',coalesce((select sum(rows) from internal_bridge),0),'pending_rows',coalesce((select sum(pending_rows) from internal_bridge),0)),
  'internal_workify_rows',case when p_project is null then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id',row_id,'original',original_amount,'charged',charged)) from internal_allocated),'[]'::jsonb) end,
  'reconciliation',jsonb_build_object(
   'sources',coalesce((select jsonb_agg(to_jsonb(t) order by source,kind) from source_totals t),'[]'::jsonb),
   'unassigned_next',jsonb_build_object('rows',(select count(*) from next_unassigned),
    'projects',(select count(*) from unassigned_projects),
    'cost',coalesce((select sum(cost) from unassigned_projects),0),'revenue',coalesce((select sum(revenue) from unassigned_projects),0),
    'details',coalesce((select jsonb_agg(to_jsonb(t)) from(select * from unassigned_projects order by greatest(abs(cost),abs(revenue)) desc,project_number limit 20)t),'[]'::jsonb)),
   'unassigned_hub',jsonb_build_object('rows',(select count(*) from unmapped_hub),
    'cost',coalesce((select round(sum(amount),2) from unmapped_hub where kind='cost'),0),
    'revenue',coalesce((select round(sum(amount),2) from unmapped_hub where kind='revenue'),0))
  ),
  'selected_months',coalesce(to_jsonb(p_months),'[]'::jsonb),'available_groups',coalesce((select jsonb_agg(name order by name) from available_groups),'[]'::jsonb),
  'summary',(select to_jsonb(t) from totals t),'projects',coalesce((select jsonb_agg(to_jsonb(r) order by r.project_number) from rollup r),'[]'::jsonb),
  'months',coalesce((select jsonb_agg(to_jsonb(m) order by month_start) from monthly m),'[]'::jsonb),
  'managers',coalesce((select jsonb_agg(name order by name) from(select distinct project_manager name from registry where project_manager<>'')m),'[]'::jsonb),
  'groups',coalesce((select jsonb_agg(name order by name) from(select distinct coalesce(nullif(business_group,''),'Ingen grupp') name from registry)m),'[]'::jsonb),
  'selected_groups',coalesce(to_jsonb(p_groups),'[]'::jsonb),
  'centers',coalesce((select jsonb_agg(code order by code) from(select distinct cost_center code from registry)c),'[]'::jsonb),
  'hub_synced_at',(select synced_at from private.hub_kpi_report_state where tenant_id=p_tenant_id),
  'hub_unmapped_rows',(select count(*) from hub_facts f where not exists(select 1 from hub_ids identity where identity.kind=case when nullif(trim(f.project),'') is not null then 'project' else 'vehicle' end and identity.value=coalesce(nullif(trim(f.project),''),f.vehicle))),
  'transactions',coalesce((select jsonb_agg(to_jsonb(e) order by date desc,id) from details e),'[]'::jsonb),
  'transaction_count',case when p_project is null then 0 else (select count(*) from evidence where p_kind is null or kind=p_kind) end,
  'excluded_rows',(select count(*) from public.kpi_import_rows r join selected s on s.project_number=trim(r.project_reference) where r.tenant_id=p_tenant_id and r.source_data?'Projektnr' and r.source_data?'Bokf datum' and r.occurred_on between p_from and p_to and (p_months is null or extract(month from r.occurred_on)::integer=any(p_months)) and (r.amount is null or (not r.is_valid and not(r.validation_errors <@ '["Kostnadsfördelning behöver granskas","Fordonsbeteckning saknar verifierad regnummerkoppling"]'::jsonb)))),
  'latest_source_date',(select max(r.occurred_on) from public.kpi_import_rows r join selected s on s.project_number=trim(r.project_reference) where r.tenant_id=p_tenant_id and r.source_data?'Projektnr' and r.source_data?'Bokf datum'),
  'unassigned_rows',(select count(*) from next_unassigned)
 ) into answer;
 return answer;
end $function$;

notify pgrst,'reload schema';
