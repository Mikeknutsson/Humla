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
 ), rule_matches as materialized (
 select r.id,m.dimension,m.priority,m.target_value,m.target_object_id
 from ranked r join public.hub_allocation_mapping_rules m on m.tenant_id=p_tenant_id
 and m.rule_status='confirmed' and m.confidence=1
 and (m.valid_from is null or m.valid_from<=r.occurred_on) and (m.valid_to is null or m.valid_to>=r.occurred_on)
 and m.data_kind in ('*',r.data_kind)
 and m.source_family in ('*',case when left(r.fp,8)='workify:' then 'Workify' when left(r.fp,5)='next:' then 'NEXT' else coalesce(r.source_system,'Other') end)
 and upper(trim(m.evidence_value))=upper(trim(case m.evidence_type
 when 'fact' then r.fp||':'||r.occurrence when 'project' then r.project_reference
 when 'vehicle_registration' then r.vehicle_registration when 'driver' then coalesce(r.source_data->>'Förare',r.employee_number)
 when 'customer' then coalesce(r.source_data->>'Kundnamn',r.source_data->>'Kundnr')
 when 'supervisor' then coalesce(r.source_data->>'Arbetsledare',coalesce(r.source_data->>'VårReferens',r.source_data->>'Vår referens'))
 when 'account' then r.account when 'article' then r.source_data->>'Artikelnummer'
 when 'supplier' then r.source_data->>'Leverantör' when 'reference' then r.description end))
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
 left join rule_targets v on v.id=r.id and v.dimension='vehicle'
 left join rule_targets p on p.id=r.id and p.dimension='project'
 left join rule_targets c on c.id=r.id and c.dimension='cost_center';
end $function$;

revoke all on function private.hub_economic_transactions_compact_v2(uuid,date,date) from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.hub_kpi_economic_reconciliation_v3(p_tenant_id uuid, p_from date, p_to date, p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '45s'
 SET jit TO 'off'
 SET work_mem TO '64MB'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare result jsonb; status_filter text:=coalesce(p_filters->>'status','included');
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if status_filter not in ('all','included','excluded_duplicate','excluded_withdrawn','excluded_accounted_elsewhere','invalid_economic_data') then raise exception 'Invalid status';end if;
 if p_page is null or p_page<0 or p_page>100000 then raise exception 'Invalid page';end if;
 with facts as materialized(select * from private.hub_economic_transactions_compact_v2(p_tenant_id,p_from,p_to)),
 totals as(select source_family,kind,currency,economic_status,count(*) rows,coalesce(sum(amount)filter(where amount::text not in ('NaN','Infinity','-Infinity')),0) amount from facts group by 1,2,3,4),
 allocations as(select source_family,kind,currency,allocation_status,count(*) rows,coalesce(sum(amount),0) amount from facts where economic_status='included' group by 1,2,3,4),
 controls as(select kind,currency,count(*) rows,coalesce(sum(amount)filter(where amount::text not in ('NaN','Infinity','-Infinity')),0) original_amount from facts group by 1,2),
 items as(select f.*,b.file_name,b.id batch_id,r.row_number,r.source_data original_source_data
 from facts f join public.kpi_import_rows r on r.id=f.row_id and r.tenant_id=p_tenant_id
 join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=p_tenant_id
 where status_filter='all' or economic_status=status_filter order by occurred_on,row_id limit 100 offset p_page*100)
 select jsonb_build_object('engineVersion','hub-economic-v2','mode','comparison_only','from',p_from,'to',p_to,
 'totals',coalesce((select jsonb_agg(to_jsonb(t) order by kind,currency,economic_status)from totals t),'[]'),
 'includedRows',(select count(*) from facts where economic_status='included'),
 'unallocatedRows',(select count(*)from facts where economic_status='included' and allocation_status<>'verified'),
 'selectedStatus',status_filter,'selectedRows',(select count(*)from facts where status_filter='all' or economic_status=status_filter),
 'allocationTotals',coalesce((select jsonb_agg(to_jsonb(a))from allocations a),'[]'),
 'sourceControls',coalesce((select jsonb_agg(to_jsonb(c))from controls c),'[]'),
 'totalScope','Imported financial source rows, not company result: no payroll estimates, Piusi allocation or internal eliminations',
 'unknownIdentityRows',(select count(*)from facts where canonical_key like 'row:%' and economic_status='included'),
 'invalidAmountRows',(select count(*)from facts where amount is null or amount::text in ('NaN','Infinity','-Infinity')),
 'page',p_page,'pageSize',100,'items',coalesce((select jsonb_agg((to_jsonb(i)-'original_source_data')||jsonb_build_object('source_data',i.original_source_data))from items i),'[]')) into result;
 return result;
end $function$;

CREATE OR REPLACE FUNCTION public.hub_vehicle_allocation_candidates_v2(p_tenant_id uuid, p_from date, p_to date, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '45s'
 SET jit TO 'off'
 SET work_mem TO '64MB'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if p_page is null or p_page<0 or p_page>100000 then raise exception 'Invalid page';end if;
 with ledger as materialized(select * from private.hub_economic_transactions_compact_v2(p_tenant_id,p_from-90,p_to) where economic_status='included'),
 requested as materialized(select * from ledger where occurred_on>=p_from and allocation_status='unallocated' order by case kind when 'revenue' then 0 else 1 end,occurred_on,row_id limit 100 offset p_page*100),
 registrations as materialized(
 select upper(regexp_replace(k.identity_value,'[[:space:]-]','','g')) registration,(array_agg(distinct k.object_id))[1] object_id
 from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
 where k.tenant_id=p_tenant_id and k.confidence=1 and lower(o.object_type)='vehicle'
 and k.identity_type in ('registration_number','vehicle_registration') group by 1 having count(distinct k.object_id)=1),
 people as materialized(
 select o.id,upper(trim(o.data->>'display_name')) name from public.hub_objects o where o.tenant_id=p_tenant_id and lower(o.object_type)='person'),
 person_matches as materialized(
 select r.row_id,(array_agg(distinct p.id))[1] person_id from requested r join people p
 on p.name=upper(trim(r.source_data->>'Förare')) group by r.row_id having count(distinct p.id)=1),
 history as materialized(
 select l.*,g.object_id known_vehicle from ledger l join registrations g on g.registration=upper(regexp_replace(l.vehicle,'[[:space:]-]','','g'))),
 history_signals as materialized(
 select r.row_id,h.known_vehicle,v.evidence_type,count(*) observations,
 count(*)::numeric/sum(count(*))over(partition by r.row_id,v.evidence_type) frequency,
 max(v.weight) weight
 from requested r join history h on h.occurred_on<r.occurred_on and h.occurred_on>=r.occurred_on-90
 cross join lateral(values
 ('historical_driver',nullif(upper(trim(r.source_data->>'Förare')),''),upper(trim(h.source_data->>'Förare')),35),
 ('historical_project',nullif(upper(trim(r.project)),''),upper(trim(h.project)),25),
 ('historical_customer',nullif(upper(trim(coalesce(r.source_data->>'Kundnamn',r.source_data->>'Kundnr'))),''),upper(trim(coalesce(h.source_data->>'Kundnamn',h.source_data->>'Kundnr'))),15),
 ('historical_supervisor',nullif(upper(trim(coalesce(r.source_data->>'Arbetsledare',coalesce(r.source_data->>'VårReferens',r.source_data->>'Vår referens')))),''),upper(trim(coalesce(h.source_data->>'Arbetsledare',coalesce(h.source_data->>'VårReferens',h.source_data->>'Vår referens')))),20)
 )v(evidence_type,requested_value,history_value,weight)
 where v.requested_value=v.history_value group by r.row_id,h.known_vehicle,v.evidence_type),
 signals as materialized(
 select r.row_id,g.object_id,'source_registration'::text evidence_type,100::numeric score,
 jsonb_build_object('registration',g.registration,'source','original') evidence
 from requested r join registrations g on g.registration=upper(regexp_replace(coalesce(nullif(r.source_data->>'RegNr',''),r.vehicle),'[[:space:]-]','','g'))
 union all
 select r.row_id,k.object_id,'canonical_project_identity',90::numeric,jsonb_build_object('identityType','next_project_number','project',r.project)
 from requested r join (
 select identity_value,(array_agg(distinct object_id))[1] object_id from public.hub_identity_keys
 where tenant_id=p_tenant_id and confidence=1 and lower(object_type)='vehicle' and identity_type in ('next_project_number','next_project_reference')
 group by identity_value having count(distinct object_id)=1
 ) k on k.identity_value=r.project
 union all
 select r.row_id,m.target_object_id,'confirmed_'||m.evidence_type,100::numeric,
 jsonb_build_object('ruleId',m.id,'from',m.valid_from,'to',m.valid_to,'priority',m.priority)
 from requested r join public.hub_allocation_mapping_rules m on m.tenant_id=p_tenant_id and m.rule_status='confirmed'
 and m.dimension='vehicle' and m.target_object_id is not null and m.confidence=1
 and (m.valid_from is null or m.valid_from<=r.occurred_on) and (m.valid_to is null or m.valid_to>=r.occurred_on)
 and m.source_family in ('*',r.source_family) and m.data_kind in ('*',r.kind)
 and upper(trim(m.evidence_value))=upper(trim(case m.evidence_type
 when 'fact' then r.canonical_key when 'project' then r.project when 'vehicle_registration' then r.vehicle
 when 'driver' then r.source_data->>'Förare' when 'customer' then coalesce(r.source_data->>'Kundnamn',r.source_data->>'Kundnr')
 when 'supervisor' then coalesce(r.source_data->>'Arbetsledare',coalesce(r.source_data->>'VårReferens',r.source_data->>'Vår referens'))
 when 'account' then r.source_data->>'Konto' when 'article' then r.source_data->>'Artikelnummer'
 when 'supplier' then r.source_data->>'Leverantör' when 'reference' then r.source_data->>'Verifikationstext' end))
 union all
 select r.row_id,g.object_id,'confirmed_driver_name',55::numeric,jsonb_build_object('ruleSource',m.rule_source)
 from requested r join public.hub_workify_driver_vehicle_rules m on m.tenant_id=p_tenant_id
 and upper(trim(m.driver_name))=upper(trim(r.source_data->>'Förare'))
 join registrations g on g.registration=upper(regexp_replace(m.target_vehicle_registration,'[[:space:]-]','','g'))
 union all
 select r.row_id,g.object_id,'transpa_same_day',60::numeric,
 jsonb_build_object('timeReportId',t.time_report_id,'startedAt',t.started_at,'precision','day_not_verified_interval')
 from requested r join person_matches pm on pm.row_id=r.row_id
 join public.hub_identity_keys person_key on person_key.tenant_id=p_tenant_id and person_key.object_id=pm.person_id
 and person_key.identity_type='transpa_employee_id' and person_key.confidence=1
 join public.kpi_transpa_time_facts t on t.tenant_id=p_tenant_id and t.employee_id=person_key.identity_value and t.work_date=r.occurred_on
 cross join lateral jsonb_array_elements_text(t.transpa_vehicle_ids) v
 join public.hub_transpa_entities e on e.tenant_id=p_tenant_id and e.entity_type='vehicle' and e.external_id=v.value
 join registrations g on g.registration=upper(regexp_replace(e.payload->>'registrationNumber','[[:space:]-]','','g'))
 union all
 select h.row_id,h.known_vehicle,h.evidence_type,round(h.weight*h.frequency,1),
 jsonb_build_object('observations',h.observations,'frequency',h.frequency,'lookbackDays',90)
 from history_signals h where h.observations>=3
 ), independent as(
 select row_id,object_id,evidence_type,max(score) score,jsonb_agg(distinct evidence) evidence from signals group by 1,2,3),
 scored as(
 select row_id,object_id,least(100,sum(score)) score,count(*) evidence_types,
 bool_or(evidence_type='source_registration' or evidence_type like 'confirmed_%' and score=100) confirmed,
 jsonb_agg(jsonb_build_object('type',evidence_type,'score',score,'details',evidence)) evidence
 from independent group by 1,2),ranked as(
 select s.*,row_number()over(partition by row_id order by score desc,confirmed desc,object_id) rank,
 lead(score)over(partition by row_id order by score desc,confirmed desc,object_id) next_score,
 count(*)filter(where confirmed)over(partition by row_id) confirmed_candidates from scored s),
 result_rows as(
 select r.row_id,r.canonical_key,r.occurred_on,r.kind,r.amount,r.currency,r.project,r.cost_center,
 coalesce(jsonb_agg(jsonb_build_object('vehicleObjectId',s.object_id,'registration',(select min(g.registration) from registrations g where g.object_id=s.object_id),'score',s.score,'rank',s.rank,'evidence',s.evidence,
 'decision',case when s.confirmed_candidates>1 then 'conflicting_confirmed_evidence'
 when s.confirmed and s.rank=1 then 'confirmed_evidence'
 when s.rank=1 and s.score>=85 and s.evidence_types>=2 and coalesce(s.score-s.next_score,100)>=20 then 'high_confidence_proposal'
 when s.rank=1 and s.score>=50 and coalesce(s.score-s.next_score,100)>=15 then 'review_proposal'
 else 'insufficient_or_conflicting_evidence' end)order by s.rank)filter(where s.object_id is not null),'[]') candidates
 from requested r left join ranked s on s.row_id=r.row_id group by r.row_id,r.canonical_key,r.occurred_on,r.kind,r.amount,r.currency,r.project,r.cost_center)
 select jsonb_build_object('engineVersion','hub-evidence-v2','scoreType','uncalibrated_evidence_score',
 'automaticGuessWrites',false,'page',p_page,'pageSize',100,'items',coalesce(jsonb_agg(to_jsonb(r)),'[]'))into result from result_rows r;
 return result;
end $function$;

