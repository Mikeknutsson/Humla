create or replace function private.hub_financial_scope_fingerprint_v1(p_tenant uuid,p_generation uuid)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('rows',sum(n),'scopes',jsonb_agg(to_jsonb(s)order by occurred_on,kind,cost_center,category))
 from(select occurred_on,kind,cost_center,category,count(*)n,sum(amount)amount from private.hub_kpi_prepared_facts
 where tenant_id=p_tenant and generation_id=p_generation group by 1,2,3,4)s;
$$;
revoke all on function private.hub_financial_scope_fingerprint_v1(uuid,uuid)from public,anon,authenticated;

create or replace function private.hub_apply_probability_mapping_v2(p_tenant uuid,p_generation uuid,p_from date,p_to date,p_limit integer default 100,p_apply boolean default false)
returns jsonb language plpgsql set search_path='' set jit='off' set plan_cache_mode='force_custom_plan' as $$
declare f record;a jsonb;target uuid;v jsonb;ev jsonb;n integer:=0;matched integer:=0;reviews integer:=0;unresolved integer:=0;before_money jsonb;rows_synced integer;fallback uuid;
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'match_access_denied'using errcode='42501';end if;
 if p_limit<1 or p_limit>500 or p_from is null or p_to is null or p_to<p_from then raise exception 'Invalid matching scope';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant)then raise exception 'Generation mismatch';end if;
 perform pg_advisory_xact_lock(hashtextextended('probability-publication:'||p_tenant,0));
 select id into strict fallback from public.hub_objects where tenant_id=p_tenant and object_type='EconomicUnit'and data->>'report_fallback'='unresolved';
 before_money:=private.hub_financial_scope_fingerprint_v1(p_tenant,p_generation);
 for f in select x.fact_id,x.occurred_on,x.unit_id,x.vehicle,x.business_group from private.hub_kpi_prepared_facts x
 where x.tenant_id=p_tenant and x.generation_id=p_generation and x.unit_id=fallback and x.occurred_on between p_from and p_to
 and(x.source='NEXT'and x.kind='cost'or x.source='Workify'and x.kind='revenue'and x.category='transport')
 and not(x.classification_source?'collection_source_unit_id')and not(x.original?'_humla_cost_rule')and not(x.original?'_humla_approved_time_offset')
 and not coalesce((x.display_original->>'_humla_excluded_from_kpi')::boolean,false)
 and not(x.classification_source?'probabilistic_mapping')
 order by (x.source='Workify')desc,x.occurred_on desc,x.fact_id limit p_limit
 loop
 a:=private.hub_match_fact_v2(p_tenant,p_generation,f.fact_id);n:=n+1;
 target:=case when a->>'decision'in('auto_match','probable_match')then(a->>'candidate')::uuid end;
 if target is not null then matched:=matched+1;elsif a->>'decision'='review'then reviews:=reviews+1;else unresolved:=unresolved+1;end if;
 if not p_apply then continue;end if;
 v:=null;
 if target is not null then
 select p.value into strict v from public.hub_objects o cross join lateral jsonb_array_elements(o.data->'periods')p where o.tenant_id=p_tenant and o.id=target and o.object_type='EconomicUnit'
 and coalesce((p.value->>'enabled')::boolean,false)and(p.value->>'valid_from')::date<=f.occurred_on and(nullif(p.value->>'valid_to','')is null or(p.value->>'valid_to')::date>=f.occurred_on);
 end if;
 ev:=jsonb_build_object('engine','hub_multisignal_v2','run_id',a->'run_id','decision',a->'decision','support',a->'confidence',
 'candidate_unit_id',a->'candidate','previous_unit_id',f.unit_id,'provisional',true,'financial_inclusion','unchanged');
 update private.hub_kpi_prepared_facts x set unit_id=coalesce(target,x.unit_id),unit_name=coalesce(v->>'name',x.unit_name),
 vehicle=case when target is not null then coalesce(v#>>'{main_vehicle,source_reference}',x.vehicle)else x.vehicle end,
 business_group=coalesce((select name from public.kpi_business_groups where tenant_id=p_tenant and id::text=v->>'business_group_id'),x.business_group),
 classification_source=(case when target is not null then x.classification_source-'unresolved_unit'else x.classification_source end)||jsonb_build_object('probabilistic_mapping',ev),
 display_original=(case when target is not null then x.display_original-'_humla_unresolved_unit'else x.display_original end)||jsonb_build_object('_humla_probability',ev)
 where x.tenant_id=p_tenant and x.generation_id=p_generation and x.fact_id=f.fact_id;
 update private.hub_kpi_prepared_display_facts d set unit_id=x.unit_id,unit_name=x.unit_name,vehicle=x.vehicle,business_group=x.business_group,original=x.display_original
 from private.hub_kpi_prepared_facts x where x.tenant_id=p_tenant and x.generation_id=p_generation and x.fact_id=f.fact_id
 and d.tenant_id=p_tenant and d.generation_id=p_generation and d.fact_id=x.fact_id;
 get diagnostics rows_synced=row_count;
 if rows_synced<>1 then raise exception 'Probability mapping display mismatch';end if;
 end loop;
 if before_money is distinct from private.hub_financial_scope_fingerprint_v1(p_tenant,p_generation)then raise exception 'Probability mapping changed financial scope';end if;
 return jsonb_build_object('evaluated',n,'automatic',matched,'review',reviews,'insufficient',unresolved,'applied',p_apply,'financial_inclusion','unchanged','limit',p_limit);
end$$;
revoke all on function private.hub_apply_probability_mapping_v2(uuid,uuid,date,date,integer,boolean)from public,anon,authenticated;

-- Dedicated phase timings identify the actual failing engine rather than
-- reporting every validation/routing failure as a distance calculation failure.
do $migration$
declare d text;needle text;calls text[]:=array[
 'hub_kpi_publish_provisional_supplier_costs_v1','hub_ps_validate_fuel_v1','hub_next_validate_revenue_identity_v1',
 'hub_next_validate_completeness_v1','hub_next_validate_reexport_generation_v1','hub_workify_validate_approved_generation_v1',
 'hub_apply_workify_article_units_v1','hub_publish_approved_time_costs_v1','hub_apply_cost_allocation_v1','hub_prepare_billable_hours_v1','hub_resolve_remaining_units_v1'];fn text;
begin
 d:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 if strpos(d,'hub_multisignal_worker_v2')>0 then raise exception 'Worker already patched';end if;
 foreach fn in array calls loop
 needle:='perform private.'||fn||'(job.tenant_id,generation);';
 if strpos(d,needle)=0 then raise exception 'Unexpected worker function: %',fn;end if;
 d:=replace(d,needle,'metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));'||chr(10)||
 'phase:='||quote_literal(fn)||';phase_started:=clock_timestamp();'||chr(10)||
 case when fn='hub_resolve_remaining_units_v1'then 'analyze private.hub_kpi_prepared_facts;analyze private.hub_kpi_prepared_display_facts;'||chr(10)else ''end||needle);
 end loop;
 needle:='update private.hub_kpi_report_generations set completed_at=clock_timestamp() where id=generation;';
 if strpos(d,needle)=0 then raise exception 'Unexpected publish boundary';end if;
 d:=replace(d,needle,$patch$
 -- hub_multisignal_worker_v2: bounded publication, never a financial filter.
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='probability_mapping';phase_started:=clock_timestamp();
 metrics:=metrics||jsonb_build_object('probability_result',private.hub_apply_probability_mapping_v2(job.tenant_id,generation,make_date(extract(year from local_now)::int-1,9,1),local_now::date,100,true));
 $patch$||needle);
 execute d;
end $migration$;
