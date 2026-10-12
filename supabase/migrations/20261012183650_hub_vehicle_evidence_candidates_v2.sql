-- Explainable evidence scores, deliberately NOT statistical probabilities.
create or replace function public.hub_vehicle_allocation_candidates_v2(p_tenant_id uuid,p_from date,p_to date,p_page integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='45s' set jit='off' set work_mem='64MB' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if p_page is null or p_page<0 or p_page>100000 then raise exception 'Invalid page';end if;
 with ledger as materialized(select * from private.hub_economic_transactions_v2(p_tenant_id,p_from-90,p_to) where economic_status='included'),
 requested as materialized(select * from ledger where occurred_on>=p_from and allocation_status='unallocated' order by occurred_on,row_id limit 100 offset p_page*100),
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
 ('historical_supervisor',nullif(upper(trim(coalesce(r.source_data->>'Arbetsledare',r.source_data->>'Vår referens'))),''),upper(trim(coalesce(h.source_data->>'Arbetsledare',h.source_data->>'Vår referens'))),20)
 )v(evidence_type,requested_value,history_value,weight)
 where v.requested_value=v.history_value group by r.row_id,h.known_vehicle,v.evidence_type),
 signals as materialized(
 select r.row_id,g.object_id,'source_registration'::text evidence_type,100::numeric score,
 jsonb_build_object('registration',g.registration,'source','original') evidence
 from requested r join registrations g on g.registration=upper(regexp_replace(coalesce(nullif(r.source_data->>'RegNr',''),r.vehicle),'[[:space:]-]','','g'))
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
 when 'supervisor' then coalesce(r.source_data->>'Arbetsledare',r.source_data->>'Vår referens')
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
 coalesce(jsonb_agg(jsonb_build_object('vehicleObjectId',s.object_id,'score',s.score,'rank',s.rank,'evidence',s.evidence,
 'decision',case when s.confirmed_candidates>1 then 'conflicting_confirmed_evidence'
 when s.confirmed and s.rank=1 then 'confirmed_evidence'
 when s.rank=1 and s.score>=85 and s.evidence_types>=2 and coalesce(s.score-s.next_score,100)>=20 then 'high_confidence_proposal'
 when s.rank=1 and s.score>=50 and coalesce(s.score-s.next_score,100)>=15 then 'review_proposal'
 else 'insufficient_or_conflicting_evidence' end)order by s.rank)filter(where s.object_id is not null),'[]') candidates
 from requested r left join ranked s on s.row_id=r.row_id group by r.row_id,r.canonical_key,r.occurred_on,r.kind,r.amount,r.currency,r.project,r.cost_center)
 select jsonb_build_object('engineVersion','hub-evidence-v2','scoreType','uncalibrated_evidence_score',
 'automaticGuessWrites',false,'page',p_page,'pageSize',100,'items',coalesce(jsonb_agg(to_jsonb(r)),'[]'))into result from result_rows r;
 return result;
end $$;
revoke all on function public.hub_vehicle_allocation_candidates_v2(uuid,date,date,integer) from public,anon;
grant execute on function public.hub_vehicle_allocation_candidates_v2(uuid,date,date,integer) to authenticated;
notify pgrst,'reload schema';

