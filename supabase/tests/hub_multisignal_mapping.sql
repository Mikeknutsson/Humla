begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
set local statement_timeout='60s';
do $$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';a uuid;b uuid;r uuid;j jsonb;c numeric;f text;money numeric;
begin
 insert into public.hub_objects(tenant_id,object_type,data)values(t,'EconomicUnit','{"name":"Synthetic candidate A"}')returning id into a;
 insert into public.hub_objects(tenant_id,object_type,data)values(t,'EconomicUnit','{"name":"Synthetic candidate B"}')returning id into b;
 insert into public.hub_match_runs(tenant_id,entity_type,source_system,source_record_id)values(t,'EconomicUnit','Workify','synthetic-regression')returning id into r;
 insert into public.hub_match_evidence(tenant_id,run_id,candidate_object_id,signal_type,source_system,weight,score,evidence)
 values(t,r,a,'driver_day','TransPA',1,.96,'{"engine":"hub_multisignal_v2"}');
 j:=public.hub_match_decide_v1(r);
 if j->>'decision'<>'probable_match'then raise exception 'Single activity signal must remain provisional';end if;
 c:=(j->>'confidence')::numeric;
 insert into public.hub_match_evidence(tenant_id,run_id,candidate_object_id,signal_type,source_system,weight,score,evidence)
 select t,r,a,'driver_day','TransPA',1,.96,'{"engine":"hub_multisignal_v2"}'from generate_series(1,20);
 j:=public.hub_match_decide_v1(r);
 if(j->>'confidence')::numeric<>c then raise exception 'Repeated correlated evidence inflated confidence';end if;
 insert into public.hub_match_evidence(tenant_id,run_id,candidate_object_id,signal_type,source_system,weight,score,evidence)
 values(t,r,a,'same_order','Workify',1,.86,'{"engine":"hub_multisignal_v2"}');
 j:=public.hub_match_decide_v1(r);
 if j->>'decision'<>'auto_match'then raise exception 'Independent temporal agreement not recognized: %',j;end if;
 insert into public.hub_match_evidence(tenant_id,run_id,candidate_object_id,signal_type,source_system,weight,score,evidence)
 values(t,r,b,'driver_day','TransPA',1,.96,'{"engine":"hub_multisignal_v2"}'),(t,r,b,'same_order','Workify',1,.86,'{"engine":"hub_multisignal_v2"}');
 j:=public.hub_match_decide_v1(r);
 if j->>'decision'<>'review'then raise exception 'Tied candidates should remain in fallback';end if;
 insert into public.hub_match_evidence(tenant_id,run_id,candidate_object_id,signal_type,source_system,weight,score,evidence)
 values(t,r,a,'registry_vehicle','Workify',1,.99,'{"engine":"hub_multisignal_v2","unique_identity":true}'),(t,r,b,'registry_vehicle','Workify',1,.99,'{"engine":"hub_multisignal_v2","unique_identity":true}');
 j:=public.hub_match_decide_v1(r);
 if j->>'decision'<>'review'then raise exception 'Conflicting confirmed identities must not choose arbitrarily';end if;
 update public.hub_match_runs set decision='human_confirmed',selected_object_id=a where id=r;
 j:=public.hub_match_decide_v1(r);
 if j->>'decision'<>'human_confirmed'or j->>'candidate'<>a::text then raise exception 'Human confirmation was overwritten';end if;
 select fact_id into strict f from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=(select active_generation from private.hub_kpi_report_state where tenant_id=t)and source='Workify'limit 1;
 select sum(amount)into money from private.hub_kpi_prepared_facts where tenant_id=t;
 perform public.hub_match_prepared_fact_v2(t,f);
 perform public.hub_match_prepared_fact_v2(t,f);
 if money is distinct from(select sum(amount)from private.hub_kpi_prepared_facts where tenant_id=t)then raise exception 'Evidence collection changed money';end if;
 if has_function_privilege('anon','public.hub_match_prepared_fact_v2(uuid,text)','execute')then raise exception 'Anonymous matcher access';end if;
end$$;
rollback;
