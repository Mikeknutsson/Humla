begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';g uuid;o uuid;rule uuid;r record;n integer;
begin
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 select id into strict o from public.hub_objects where tenant_id=t and object_type='EconomicUnit' and data->>'report_fallback'='unresolved';
 if (select count(*)from public.hub_object_relations where tenant_id=t and to_object_id=o and relation_type='reports_in' and status='active' and confidence=1)<>2 then raise exception 'Two confirmed collection memberships required';end if;
 if exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and unit_name in('SOU57P','MDE75S'))then raise exception 'Grouped source units remain as separate rows';end if;
 if not exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and unit_id=o and vehicle='SOU57P' and project='2063' and classification_source->>'remaining_unit_resolution'='confirmed_report_collection')then raise exception 'Source identities were lost';end if;
 if exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and classification_source->>'remaining_unit_resolution'='confirmed_report_collection' and classification_source?'unresolved_unit')then raise exception 'Confirmed collection incorrectly labeled unresolved';end if;
 n:=private.hub_kpi_apply_report_collections_v1(t,g);
 if n<>0 then raise exception 'Repeated collection publication is not idempotent';end if;
 select id into strict rule from public.hub_cost_allocation_rules where tenant_id=t and name='Bygg & Anläggning – gemensamma släp/jiggar' and source_scope->'source_unit_names'?'WCN517';
 for r in select a.original_fact_id,(a.before_fact->>'amount')::numeric amount,a.recipients,a.before_fact from private.hub_cost_allocation_applied_v1 a
 where a.tenant_id=t and a.generation_id=g and a.rule_id=rule and a.before_fact->>'vehicle'='WCN517'
 loop
  if (select sum(f.amount)from private.hub_kpi_prepared_facts f where f.tenant_id=t and f.generation_id=g and f.original#>>'{_humla_cost_rule,original_fact_id}'=r.original_fact_id) is distinct from r.amount then raise exception 'WCN costs omitted or counted twice';end if;
  if exists(select 1 from private.hub_kpi_prepared_facts f where f.tenant_id=t and f.generation_id=g and f.fact_id=r.original_fact_id)then raise exception 'Original cost remains alongside allocations';end if;
  if (r.before_fact->>'occurred_on')::date<'2026-09-07' and jsonb_array_length(r.recipients)<>7 then raise exception 'Historical active recipient count';end if;
 end loop;
 if not found then raise exception 'WCN allocations missing';end if;
 if exists(select 1 from private.hub_kpi_prepared_facts f join private.hub_kpi_prepared_display_facts d using(tenant_id,generation_id,fact_id)where f.tenant_id=t and f.generation_id=g and(f.unit_id,f.amount,f.project,f.cost_center)is distinct from(d.unit_id,d.amount,d.project,d.cost_center))then raise exception 'Detailed and display facts disagree';end if;
 perform set_config('request.jwt.claim.sub','',true);
 begin
  perform private.hub_kpi_apply_report_collections_v1(t,g);
  raise exception 'Anonymous operation allowed';
 exception when insufficient_privilege then null;end;
end $$;
rollback;
