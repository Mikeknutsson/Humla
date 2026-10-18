-- Reuse the existing Hub match ledger. Confidence is a support score, not a
-- calibrated probability. Financial inclusion never depends on this score.
create index if not exists hub_match_evidence_run_candidate_idx on public.hub_match_evidence(tenant_id,run_id,candidate_object_id);
create index if not exists hub_match_run_source_lookup_idx on public.hub_match_runs(tenant_id,entity_type,source_system,source_record_id);

create or replace function private.hub_match_scores_v2(p_run uuid)
returns table(object_id uuid,support numeric,families integer,systems integer,anchor boolean,temporal boolean,signals jsonb)
language sql stable set search_path='' as $$
 with valid as(
 select e.*,case
 when e.signal_type in('registry_vehicle','registry_project','document_registration','same_order')then 'document'
 when e.signal_type in('driver_day','driver_history')then 'driver_activity'
 when e.signal_type='dated_person_membership'then 'assignment'
 when e.signal_type='confirmed_learning'then 'human_history'end family,
 case when e.signal_type in('driver_day','driver_history')then 'TransPA'
 when e.signal_type in('dated_person_membership','confirmed_learning')then 'Humla Hub'else r.source_system end origin
 from public.hub_match_evidence e join public.hub_match_runs r on r.id=e.run_id and r.tenant_id=e.tenant_id
 join public.hub_objects o on o.tenant_id=r.tenant_id and o.id=e.candidate_object_id and o.object_type=r.entity_type and o.status='active'
 where e.run_id=p_run and e.evidence->>'engine'='hub_multisignal_v2'and e.weight>0 and e.weight<='10'
 and e.score>=0 and e.score<=1
 ), dedup as(
 select candidate_object_id,family,origin,max(score)score,max(weight)weight,
 bool_or(signal_type in('registry_vehicle','registry_project')and evidence->>'unique_identity'='true')anchor,
 bool_or(signal_type in('driver_day','dated_person_membership'))temporal,
 jsonb_agg(jsonb_build_object('type',signal_type,'source',origin,'score',score,'evidence',evidence))signals
 from valid where family is not null group by 1,2,3
 ), grouped as(
 select candidate_object_id,count(distinct family)::int families,count(distinct origin)::int systems,
 sum(score*weight)/sum(weight)weighted,bool_or(anchor)anchor,bool_or(temporal)temporal,jsonb_agg(signals)signals
 from dedup group by 1
 )select candidate_object_id,
 round(least(0.99,case when anchor then weighted when families>=2 and systems>=2 and temporal then weighted+0.03 else least(weighted,0.89)end),4),
 families,systems,coalesce(anchor,false),coalesce(temporal,false),signals from grouped;
$$;
revoke all on function private.hub_match_scores_v2(uuid)from public,anon,authenticated;

create or replace function public.hub_match_decide_v1(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.hub_match_runs;top_row record;runner numeric;outcome text;conflict boolean;ranked jsonb;
begin
 select * into r from public.hub_match_runs where id=p_run_id for update;
 if not found or auth.uid()is null or not public.hub_has_permission(r.tenant_id,'kpi.manage')then raise exception 'match_access_denied'using errcode='42501';end if;
 if r.decision in('human_confirmed','human_corrected','human_rejected')then return jsonb_build_object('run_id',r.id,'decision',r.decision,'candidate',r.selected_object_id,'preserved_human_decision',true);end if;
 select * into top_row from private.hub_match_scores_v2(r.id)order by support desc,anchor desc,object_id limit 1;
 if not found then
 update public.hub_match_runs set selected_object_id=null,confidence=null,decision='insufficient_evidence',status='unresolved',explanation=jsonb_build_object('rule','hub_multisignal_v2','reason','no_qualified_evidence','financial_inclusion','unchanged'),updated_at=now()where id=r.id;
 return jsonb_build_object('run_id',r.id,'decision','insufficient_evidence','candidate',null);
 end if;
 select support into runner from private.hub_match_scores_v2(r.id)order by support desc,anchor desc,object_id offset 1 limit 1;
 select count(*)>1 into conflict from private.hub_match_scores_v2(r.id)where anchor;
 outcome:=case when top_row.support>=0.92 and not conflict and(top_row.anchor or(top_row.families>=2 and top_row.systems>=2 and top_row.temporal))and(runner is null or top_row.support-runner>=0.12)then 'auto_match'
 when top_row.support>=0.70 and not conflict and(runner is null or top_row.support-runner>=0.05)then 'probable_match'
 when top_row.support>=0.70 then 'review'else 'insufficient_evidence'end;
 select coalesce(jsonb_agg(to_jsonb(s)order by s.support desc,s.object_id),'[]')into ranked from private.hub_match_scores_v2(r.id)s;
 update public.hub_match_runs set selected_object_id=case when outcome in('auto_match','probable_match')then top_row.object_id end,confidence=top_row.support,
 decision=outcome,status=case when outcome in('auto_match','probable_match')then 'matched'when outcome='review'then 'needs_review'else 'unresolved'end,
 explanation=jsonb_build_object('rule','hub_multisignal_v2','score_kind','heuristic_support_not_probability','candidates',ranked,'top_candidate',top_row.object_id,
 'second_score',runner,'identity_conflict',conflict,'auto_threshold',0.92,'minimum_margin',0.12,'financial_inclusion','unchanged'),updated_at=now()where id=r.id;
 return jsonb_build_object('run_id',r.id,'decision',outcome,'candidate',top_row.object_id,'confidence',top_row.support,'second_score',runner,'candidates',ranked,'financial_inclusion','unchanged');
end$$;
revoke all on function public.hub_match_decide_v1(uuid)from public,anon;
grant execute on function public.hub_match_decide_v1(uuid)to authenticated;

create or replace function private.hub_match_fact_v2(p_tenant uuid,p_generation uuid,p_fact text)
returns jsonb language plpgsql set search_path='' set jit='off' set plan_cache_mode='force_custom_plan' as $$
declare f private.hub_kpi_prepared_facts;r public.hub_match_runs;payload jsonb;person uuid;persons integer;answer jsonb;
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'match_access_denied'using errcode='42501';end if;
 select * into strict f from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and fact_id=p_fact;
 perform pg_advisory_xact_lock(hashtextextended('match-v2:'||p_tenant||':'||p_generation||':'||p_fact,0));
 select * into r from public.hub_match_runs where tenant_id=p_tenant and entity_type='EconomicUnit'and source_system=f.source and source_record_id=p_generation||':'||p_fact order by created_at desc,id limit 1 for update;
 if r.decision in('human_confirmed','human_corrected','human_rejected')then return public.hub_match_decide_v1(r.id);end if;
 payload:=jsonb_build_object('generation_id',p_generation,'fact_id',p_fact,'occurred_on',f.occurred_on,'project_reference',f.project,'vehicle_registration',f.vehicle,
 'driver_name',nullif(trim(f.original->>'Förare'),''),'customer',f.original->>'Kundnr','article',f.original->>'Artikelnummer','order_number',f.original->>'Ordernummer','category',f.category,'cost_center',f.cost_center,
 'supplier',f.original->>'Leverantör','account',f.account,'description',f.description,'source_value',f.project);
 if r.id is null then
 insert into public.hub_match_runs(tenant_id,entity_type,source_system,source_record_id,source_payload)values(p_tenant,'EconomicUnit',f.source,p_generation||':'||p_fact,payload)returning * into r;
 else update public.hub_match_runs set source_payload=payload where id=r.id;end if;
 delete from public.hub_match_evidence where tenant_id=p_tenant and run_id=r.id and evidence->>'engine'='hub_multisignal_v2';
 -- Only typed adapter fields can seed identities. Amounts, account numbers and
 -- arbitrary text values must never accidentally match another system's ID.
 with refs as(
 select 'vehicle'kind,v.ref from(values(nullif(trim(f.vehicle),'')),(nullif(trim(f.original->>'RegNr'),'')),(nullif(trim(f.original->>'Fordon'),'')))v(ref)where v.ref is not null
 union select 'project',f.project where f.source='NEXT'and f.project is not null
 ), resolved_keys as(
 select distinct v.kind,v.ref,k.object_id
 from(select distinct kind,ref from refs)v join public.hub_identity_keys k on k.tenant_id=p_tenant and k.confidence=1
 and((v.kind='vehicle'and k.object_type='Vehicle'and k.identity_type in('registration_number','vehicle_registration','workify_vehicle_label')and upper(trim(k.identity_value))=upper(trim(v.ref)))
 or(v.kind='project'and k.object_type='Project'and k.identity_type='next_project_number'and k.identity_value=v.ref))
 ), identities as(select *,count(*)over(partition by kind,ref)n from resolved_keys),targets as(
 select distinct u.id,v.kind,v.ref,v.object_id,v.n
 from identities v join public.hub_objects src on src.tenant_id=p_tenant and src.id=v.object_id and src.status='active'
 join public.hub_objects u on u.tenant_id=p_tenant and u.object_type='EconomicUnit'and u.status='active'
 cross join lateral jsonb_array_elements(coalesce(u.data->'periods','[]'))p
 cross join lateral jsonb_array_elements(coalesce(p.value->'members','[]'))m
 where coalesce((p.value->>'enabled')::boolean,false)and(p.value->>'valid_from')::date<=f.occurred_on
 and(nullif(p.value->>'valid_to','')is null or(p.value->>'valid_to')::date>=f.occurred_on)
 and m.value->>'object_id'=v.object_id::text and m.value->>'resolution'='confirmed'
 and not exists(select 1 from private.hub_kpi_project_exclusions x where x.tenant_id=p_tenant and x.enabled and x.economic_unit_id=u.id)
 )insert into public.hub_match_evidence(tenant_id,run_id,candidate_object_id,signal_type,source_system,signal_value,weight,score,evidence)
 select p_tenant,r.id,id,case kind when 'vehicle'then 'registry_vehicle'else 'registry_project'end,f.source,ref,1,0.99,
 jsonb_build_object('engine','hub_multisignal_v2','canonical_source_id',object_id,'unique_identity',n=1,'date',f.occurred_on)from targets;
 -- Driver-name resolution is exact and unique. Same-person links connect existing
 -- canonical aliases; no guessed permanent person or vehicle identity is created.
 select count(distinct o.id),(array_agg(distinct o.id))[1]into persons,person from public.hub_objects o where o.tenant_id=p_tenant and o.object_type='Person'and o.status='active'
 and nullif(payload->>'driver_name','')is not null and(upper(trim(o.data->>'display_name'))=upper(payload->>'driver_name')or exists(
 select 1 from public.hub_identity_keys k where k.tenant_id=p_tenant and k.object_id=o.id and k.identity_type='next_person_name'and k.confidence=1 and upper(trim(k.identity_value))=upper(payload->>'driver_name')));
 if persons=1 then
 with people as(
 select person id union select case when a.from_object_id=person then a.to_object_id else a.from_object_id end from public.hub_object_relations a
 where a.tenant_id=p_tenant and a.relation_type='same_person'and a.confidence=1 and a.status='active'and person in(a.from_object_id,a.to_object_id)
 and(a.valid_from is null or(a.valid_from at time zone 'Europe/Stockholm')::date<=f.occurred_on)and(a.valid_to is null or(a.valid_to at time zone 'Europe/Stockholm')::date>=f.occurred_on)
 ), activity as(
 select distinct t.work_date,kv.object_id vehicle_id
 from private.hub_kpi_prepared_kpi_transpa_time_facts t
 left join public.hub_identity_keys kp on kp.tenant_id=p_tenant and kp.identity_type='transpa_employee_id'and kp.confidence=1 and kp.identity_value=t.employee_id
 cross join lateral jsonb_array_elements_text(t.transpa_vehicle_ids)v
 join public.hub_identity_keys kv on kv.tenant_id=p_tenant and kv.object_type='Vehicle'and kv.identity_type='transpa_vehicle_id'and kv.confidence=1 and kv.identity_value=v.value
 where t.tenant_id=p_tenant and t.generation_id=p_generation and t.work_date between f.occurred_on-30 and f.occurred_on and t.work_hours>0
 and coalesce(t.person_object_id,kp.object_id)in(select id from people)
 ), observed as(
 select vehicle_id,'driver_day'::text signal,0.96::numeric score,count(distinct work_date)n from activity where work_date=f.occurred_on group by 1
 union all
 select vehicle_id,'driver_history',0.82,count(distinct work_date)from activity where work_date<f.occurred_on group by 1 having count(distinct work_date)>=5
 ), targets as(
 select distinct u.id,a.* from observed a join public.hub_objects u on u.tenant_id=p_tenant and u.object_type='EconomicUnit'and u.status='active'
 cross join lateral jsonb_array_elements(coalesce(u.data->'periods','[]'))p cross join lateral jsonb_array_elements(coalesce(p.value->'members','[]'))m
 where coalesce((p.value->>'enabled')::boolean,false)and(p.value->>'valid_from')::date<=f.occurred_on and(nullif(p.value->>'valid_to','')is null or(p.value->>'valid_to')::date>=f.occurred_on)
 and m.value->>'object_id'=a.vehicle_id::text and m.value->>'resolution'='confirmed'
 and not exists(select 1 from private.hub_kpi_project_exclusions x where x.tenant_id=p_tenant and x.enabled and x.economic_unit_id=u.id)
 )insert into public.hub_match_evidence(tenant_id,run_id,candidate_object_id,signal_type,source_system,signal_value,weight,score,evidence)
 select p_tenant,r.id,id,signal,'TransPA',person::text,1,score,jsonb_build_object('engine','hub_multisignal_v2','person_id',person,'vehicle_id',vehicle_id,'observed_days',n,'date',f.occurred_on)from targets;
 end if;
 -- Same-order context is deliberately weaker than an explicit registration.
 -- Material/tipping and previously probabilistically routed rows cannot teach it.
 if f.source='Workify'and f.category='transport'and nullif(payload->>'order_number','')is not null then
 insert into public.hub_match_evidence(tenant_id,run_id,candidate_object_id,signal_type,source_system,signal_value,weight,score,evidence)
 select distinct p_tenant,r.id,s.unit_id,'same_order','Workify',payload->>'order_number',1,0.86,
 jsonb_build_object('engine','hub_multisignal_v2','date',f.occurred_on,'same_customer',true)
 from private.hub_kpi_prepared_facts s join public.hub_objects u on u.tenant_id=p_tenant and u.id=s.unit_id and u.object_type='EconomicUnit'and u.data->>'report_fallback'is distinct from'unresolved'
 where s.tenant_id=p_tenant and s.generation_id=p_generation and s.source='Workify'and s.kind='revenue'and s.category='transport'and s.occurred_on=f.occurred_on
 and s.original->>'Ordernummer'=payload->>'order_number'and s.original->>'Kundnr'=payload->>'customer'
 and not(s.classification_source?'probabilistic_mapping')and s.fact_id<>f.fact_id
 and not coalesce((s.display_original->>'_humla_excluded_from_kpi')::boolean,false);
 end if;
 -- Literal registrations in a document are suggestions, not exact registry anchors.
 with refs as(
 select distinct x[1]ref from regexp_matches(upper(concat_ws(' ',f.description,f.original->>'Verifikationstext',f.original->>'ArtikelKommentar')),'\m([A-Z]{3}[0-9]{2}[A-Z0-9])\M','g')x
 ), vehicles as(
 select distinct k.object_id,v.ref from refs v join public.hub_identity_keys k on k.tenant_id=p_tenant and k.object_type='Vehicle'and k.confidence=1
 and k.identity_type in('registration_number','vehicle_registration')and upper(trim(k.identity_value))=v.ref
 )insert into public.hub_match_evidence(tenant_id,run_id,candidate_object_id,signal_type,source_system,signal_value,weight,score,evidence)
 select distinct p_tenant,r.id,u.id,'document_registration',f.source,v.ref,1,0.84,jsonb_build_object('engine','hub_multisignal_v2','vehicle_id',v.object_id,'date',f.occurred_on)
 from vehicles v join public.hub_objects u on u.tenant_id=p_tenant and u.object_type='EconomicUnit'and u.status='active'
 cross join lateral jsonb_array_elements(coalesce(u.data->'periods','[]'))p cross join lateral jsonb_array_elements(coalesce(p.value->'members','[]'))m
 where coalesce((p.value->>'enabled')::boolean,false)and(p.value->>'valid_from')::date<=f.occurred_on
 and(nullif(p.value->>'valid_to','')is null or(p.value->>'valid_to')::date>=f.occurred_on)
 and m.value->>'object_id'=v.object_id::text and m.value->>'resolution'='confirmed'
 and not exists(select 1 from private.hub_kpi_project_exclusions e where e.tenant_id=p_tenant and e.enabled and e.economic_unit_id=u.id);
 -- A learned pattern must be backed by distinct human decisions, not repeated
 -- clicks or automatic matches. It never becomes a permanent identity key.
 insert into public.hub_match_evidence(tenant_id,run_id,candidate_object_id,signal_type,source_system,signal_value,weight,score,evidence)
 select p_tenant,r.id,u.id,'confirmed_learning','Humla Hub',p.signature,1,least(p.confidence,0.96),
 jsonb_build_object('engine','hub_multisignal_v2','pattern_id',p.id,'confirmations',p.confirmations,'contradictions',p.contradictions)
 from public.hub_learned_match_patterns p join public.hub_objects u on u.tenant_id=p_tenant and u.id::text=p.metadata->>'target_object_id'and u.object_type='EconomicUnit'and u.status='active'
 where p.tenant_id=p_tenant and p.pattern_type='EconomicUnit'and p.state='trusted'and p.contradictions=0
 and p.signature=md5(concat_ws('|',lower(f.source),'economicunit',coalesce(payload->>'supplier',''),coalesce(payload->>'account',''),coalesce(payload->>'article',''),coalesce(payload->>'description',''),coalesce(payload->>'source_value','')))
 and(select count(distinct b.run_id)from public.hub_match_feedback b where b.tenant_id=p_tenant and b.pattern_id=p.id and b.selected_object_id=u.id and b.decision in('confirmed','corrected')and b.decided_by<>'system')>=3
 and exists(select 1 from jsonb_array_elements(coalesce(u.data->'periods','[]'))v where coalesce((v->>'enabled')::boolean,false)and(v->>'valid_from')::date<=f.occurred_on and(nullif(v->>'valid_to','')is null or(v->>'valid_to')::date>=f.occurred_on));
 answer:=public.hub_match_decide_v1(r.id);
 return answer||jsonb_build_object('fact_id',f.fact_id,'generation_id',p_generation,'amount_unchanged',true);
end$$;
revoke all on function private.hub_match_fact_v2(uuid,uuid,text)from public,anon,authenticated;

create or replace function public.hub_match_prepared_fact_v2(p_tenant uuid,p_fact text)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='25s' as $$
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'match_access_denied'using errcode='42501';end if;
 if length(p_fact)>500 then raise exception 'Invalid fact identity';end if;
 return private.hub_match_fact_v2(p_tenant,private.hub_kpi_active_report_generation_v1(p_tenant),p_fact);
end$$;
revoke all on function public.hub_match_prepared_fact_v2(uuid,text)from public,anon;
grant execute on function public.hub_match_prepared_fact_v2(uuid,text)to authenticated;
notify pgrst,'reload schema';
