begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';g uuid;o uuid;a jsonb;b jsonb;r jsonb;
begin
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 select id into strict o from public.hub_objects where tenant_id=t and object_type='EconomicUnit' and data->>'report_fallback'='unresolved';
 if exists(select 1 from private.hub_kpi_report_facts_v1 f where f.tenant_id=t and f.generation_id=g and not exists(select 1 from public.hub_objects u where u.tenant_id=t and u.id=f.unit_id and u.object_type='EconomicUnit'))then raise exception 'A financial row is still hidden outside unit totals';end if;
 if exists(select 1 from private.hub_kpi_prepared_facts f where f.tenant_id=t and f.generation_id=g and f.vehicle='JAK62T' and f.occurred_on>='2026-10-01' and f.unit_name<>'SPN03J')then raise exception 'Latest JAK mapping not applied';end if;
 if not exists(select 1 from private.hub_kpi_prepared_facts f where f.tenant_id=t and f.generation_id=g and f.fact_id='60a1dc32-d030-4a09-9432-0e34545b3073' and f.project='4004' and f.amount=20940 and f.cost_center='20')then raise exception 'Exact Workify invoice project resolution missing';end if;
 if exists(select 1 from private.hub_kpi_prepared_display_facts d join private.hub_kpi_prepared_facts f using(generation_id,tenant_id,fact_id)where f.generation_id=g and f.tenant_id=t and (d.unit_id,d.project,d.cost_center)is distinct from(f.unit_id,f.project,f.cost_center))then raise exception 'Display and detailed facts disagree';end if;
 r:=public.hub_project_revenue_statement_v1(t,'d0e501bc-b300-479e-8941-e9227b635113');
 if (r->>'imported_project_revenue')::numeric<>485797.54 or (r->>'unperiodized_difference')::numeric<>0.46 then raise exception 'Project source statement counted twice or omitted invoice: %',r;end if;
 select jsonb_build_object('economic_units',jsonb_agg(jsonb_build_object('key',unit_id,'revenue',revenue,'cost',cost,'result',revenue-cost,'rows',rows,'children','[]'::jsonb)))into a
 from(select unit_id,sum(amount)filter(where kind='revenue')revenue,sum(amount)filter(where kind='cost')cost,count(*)rows from private.hub_kpi_report_facts_v1 where tenant_id=t and generation_id=g and occurred_on between '2026-09-01'and'2026-09-30'group by unit_id)x;
 b:=private.hub_kpi_mapped_units_projection_v1(t,a);
 if jsonb_array_length(a->'economic_units')<>jsonb_array_length(b->'economic_units')then raise exception 'Projection hides financial unit rows';end if;
 if not exists(select 1 from jsonb_array_elements(b->'economic_units')v where v->>'key'=o::text and v->>'is_fallback'='true' and v->>'distance_mil' is null)then raise exception 'Collection identity/ratios missing';end if;
end $$;
-- No second mutation on the same generation.
select private.hub_resolve_remaining_units_v1(tenant_id,active_generation) from private.hub_kpi_report_state where tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b';
rollback;
