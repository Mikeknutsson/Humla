create or replace view private.hub_confirmed_allocation_rules_v2 with(security_invoker=true) as
with identities as (
 select k.tenant_id,lower(o.object_type) object_type,upper(trim(k.identity_value)) value,
 count(distinct k.object_id) n,(array_agg(distinct k.object_id))[1] object_id
 from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
 where k.confidence=1 and k.identity_type in ('registration_number','next_project_number')
 group by 1,2,3
)
select m.id,m.tenant_id,m.dimension,m.evidence_type,m.evidence_value,m.target_value,m.target_object_id,
 m.source_family,m.data_kind,m.valid_from,m.valid_to,m.priority,m.confidence,m.rule_status
from public.hub_allocation_mapping_rules m
union all
select a.id,a.tenant_id,a.dimension,case a.reference_type when 'fact' then 'legacy_fact' when 'vehicle' then 'vehicle_registration' else a.reference_type end,
 upper(trim(a.reference)),a.target,k.object_id,a.source,a.kind,a.valid_from,a.valid_to,
 case a.reference_type when 'fact' then 0 when 'vehicle' then 10 when 'project' then 20 else 50 end,
 case when a.dimension='cost_center' or k.n=1 then 1::numeric else 0::numeric end,'confirmed'
from public.kpi_dashboard_allocations a
left join identities k on k.tenant_id=a.tenant_id and k.value=upper(trim(a.target))
 and k.object_type=case a.dimension when 'vehicle' then 'vehicle' when 'project' then 'project' end
where a.dimension in ('cost_center','vehicle','project');
revoke all on private.hub_confirmed_allocation_rules_v2 from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.hub_economic_transactions_compact_v2(p_tenant_id uuid, p_from date, p_to date)
 RETURNS TABLE(row_id uuid, canonical_key text, kind text, occurred_on date, amount numeric, currency text, source_family text, economic_status text, allocation_status text, vehicle_object_id uuid, vehicle text, project text, cost_center text, source_data jsonb, validation_errors jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
 SET work_mem TO '64MB'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then
 raise exception 'KPI access required' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 then raise exception 'Invalid period';end if;
 return query with base as materialized (
 select r.id,r.tenant_id,r.batch_id,r.row_number,r.data_kind,r.occurred_on,r.amount,r.quantity,r.currency,
 r.vehicle_object_id,r.vehicle_registration,r.employee_number,r.project_reference,r.cost_center,r.source_system,r.description,r.account,r.validation_errors,
 jsonb_build_object('Konto',r.source_data->'Konto','RegNr',r.source_data->'RegNr','Förare',r.source_data->'Förare','Kundnamn',r.source_data->'Kundnamn','Kundnr',r.source_data->'Kundnr',
 'Arbetsledare',r.source_data->'Arbetsledare','VårReferens',r.source_data->'VårReferens','Vår referens',r.source_data->'Vår referens',
 'Artikelnummer',r.source_data->'Artikelnummer','Leverantör',r.source_data->'Leverantör') source_data,
 b.created_at imported_at,
 private.hub_economic_key_v2(r.data_kind,r.occurred_on,r.amount,r.quantity,r.currency,r.source_data,r.id::text) fp,
 case
 when coalesce(r.validation_errors,'[]') ? 'Importen återtagen eller ersatt; ingår inte i beräkningar' then 'excluded_withdrawn'
 when coalesce(r.validation_errors,'[]') ? 'Fakturan finns i NeXT intäktsbokföring; fakturaunderlag räknas inte som ytterligare intäkt' then 'excluded_accounted_elsewhere'
 when r.occurred_on is null or r.amount is null or r.amount::text in ('NaN','Infinity','-Infinity') then 'invalid_economic_data'
 when r.is_valid then 'eligible'
 when r.validation_errors <> '[]'::jsonb and not exists (
 select 1 from jsonb_array_elements_text(coalesce(r.validation_errors,'[]')) e
 where e not in ('Kostnadsfördelning behöver granskas','Fordonsbeteckning saknar verifierad regnummerkoppling','Workify-artikeln ska till fordon: registreringsnummer behöver mappas')
 and e not like 'Ej mappad Workify-artikel:%') then 'eligible'
 else 'invalid_economic_data' end eligibility
 from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 where r.tenant_id=p_tenant_id and r.data_kind in ('cost','revenue')
 and (r.occurred_on between p_from and p_to or r.occurred_on is null)
 ), occurrences as materialized (
 select b.*,row_number() over(partition by tenant_id,data_kind,fp collate "C",batch_id,eligibility collate "C" order by row_number,id) occurrence
 from base b
 ), ranked as (
 select o.*,row_number() over(partition by tenant_id,data_kind,fp collate "C",occurrence,eligibility collate "C" order by imported_at,batch_id,row_number,id) copy_rank
 from occurrences o
 ), registrations as materialized (
 select upper(regexp_replace(k.identity_value,'[[:space:]-]','','g')) registration,
 (array_agg(distinct k.object_id))[1] object_id
 from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
 where k.tenant_id=p_tenant_id and k.confidence=1 and lower(o.object_type)='vehicle'
 and k.identity_type in ('registration_number','vehicle_registration')
 group by 1 having count(distinct k.object_id)=1
 ), available_rules as materialized (
 select * from private.hub_confirmed_allocation_rules_v2 where tenant_id=p_tenant_id and rule_status='confirmed' and confidence=1
 ), evidence_types as (select distinct evidence_type from available_rules),
 expanded_evidence as (
 select r.*,t.evidence_type,upper(trim(case t.evidence_type
 when 'fact' then r.fp||':'||r.occurrence when 'legacy_fact' then r.id::text
 when 'project' then r.project_reference when 'vehicle_registration' then r.vehicle_registration
 when 'driver' then coalesce(r.source_data->>'Förare',r.employee_number)
 when 'customer' then coalesce(r.source_data->>'Kundnamn',r.source_data->>'Kundnr')
 when 'supervisor' then coalesce(r.source_data->>'Arbetsledare',r.source_data->>'VårReferens',r.source_data->>'Vår referens')
 when 'account' then r.account when 'article' then r.source_data->>'Artikelnummer'
 when 'supplier' then r.source_data->>'Leverantör' when 'reference' then r.description end)) evidence_value
 from ranked r cross join evidence_types t where r.eligibility='eligible'
 ), rule_matches as materialized (
 select r.fp||':'||r.occurrence id,m.dimension,m.priority,m.target_value,m.target_object_id
 from expanded_evidence r join available_rules m on m.evidence_type=r.evidence_type
 and upper(trim(m.evidence_value))=r.evidence_value
 and (m.valid_from is null or m.valid_from<=r.occurred_on) and (m.valid_to is null or m.valid_to>=r.occurred_on)
 and m.data_kind in ('*',r.data_kind)
 and m.source_family in ('*',case when left(r.fp,8)='workify:' then 'Workify' when left(r.fp,5)='next:' then 'NEXT' else coalesce(r.source_system,'Other') end)
 ), rule_priority as (select id,dimension,min(priority) priority from rule_matches group by 1,2),
 rule_targets as materialized (
 select m.id,m.dimension,m.priority,count(distinct m.target_value) targets,
 case when count(distinct m.target_value)=1 then min(m.target_value) end target_value,
 case when count(distinct m.target_object_id)=1 then (array_agg(distinct m.target_object_id)filter(where m.target_object_id is not null))[1] end target_object_id
 from rule_matches m join rule_priority p using(id,dimension,priority) group by 1,2,3
 )
 select r.id,r.fp||':'||r.occurrence,r.data_kind,r.occurred_on,r.amount,r.currency,
 case when left(r.fp,8)='workify:' then 'Workify' when left(r.fp,5)='next:' then 'NEXT' else coalesce(r.source_system,'Other') end,
 case when r.eligibility<>'eligible' then r.eligibility when r.copy_rank>1 then 'excluded_duplicate' else 'included' end,
 case when v.targets>1 then 'conflicting' when coalesce(case when v.priority=0 then v.target_object_id end,r.vehicle_object_id,g.object_id,v.target_object_id) is not null then 'verified' else 'unallocated' end,
 case when v.targets>1 then null else coalesce(case when v.priority=0 then v.target_object_id end,r.vehicle_object_id,g.object_id,v.target_object_id) end,
 case when v.targets>1 then null else coalesce(case when v.priority=0 then v.target_value end,r.vehicle_registration,v.target_value) end,
 case when p.targets>1 then null else coalesce(case when p.priority=0 then p.target_value end,r.project_reference,p.target_value) end,
 case when c.targets>1 then null else coalesce(case when c.priority=0 then c.target_value end,nullif(r.cost_center,''),c.target_value) end,
 r.source_data,r.validation_errors from ranked r
 left join registrations g on g.registration=upper(regexp_replace(r.vehicle_registration,'[[:space:]-]','','g'))
 left join rule_targets v on v.id=r.fp||':'||r.occurrence and v.dimension='vehicle'
 left join rule_targets p on p.id=r.fp||':'||r.occurrence and p.dimension='project'
 left join rule_targets c on c.id=r.fp||':'||r.occurrence and c.dimension='cost_center';
end $function$;

