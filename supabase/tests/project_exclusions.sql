begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';g uuid;r jsonb;n integer;raw_revenue numeric;visible_revenue numeric;excluded_revenue numeric;
begin
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 n:=private.hub_kpi_publish_project_exclusions_v1(t,g);
 if n<>0 then raise exception 'Repeated exclusion publication changed assignments';end if;
 if not exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and fact_id='7dbeb616-40fc-4ff8-aa4c-de80526a70d3' and amount=335797.54 and cost_center='unclassified' and project is null and display_original->>'_humla_excluded_from_kpi'='true')then raise exception 'Exact invoice rollback/preservation failed';end if;
 if exists(select 1 from private.hub_kpi_report_facts_v1 where tenant_id=t and generation_id=g and(project='12716'or original->>'Projektnr'='12716'))then raise exception 'Excluded project remains in KPI financial scope';end if;
 select sum(amount)into raw_revenue from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and kind='revenue';
 select sum(amount)into visible_revenue from private.hub_kpi_report_facts_v1 where tenant_id=t and generation_id=g and kind='revenue';
 select sum(amount)into excluded_revenue from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and kind='revenue'and display_original->>'_humla_excluded_from_kpi'='true';
 if raw_revenue<>visible_revenue+excluded_revenue then raise exception 'Financial source conservation failed';end if;
 r:=public.hub_kpi_overview_months_v1(t,2026,array[9],'30','{}');
 if (r#>>'{metrics,revenue}')::numeric<>7251423.88 then raise exception 'Transport revenue not restored';end if;
 if exists(select 1 from jsonb_array_elements(r->'economic_units')u where u->>'label'='Rivning Kv Älgen')then raise exception 'Excluded unit still displayed';end if;
 if jsonb_array_length(r->'excluded_projects')<>1 then raise exception 'Explicit scope notice missing';end if;
 if abs((public.hub_project_revenue_statement_v1(t,'d0e501bc-b300-479e-8941-e9227b635113')->>'imported_project_revenue')::numeric-485797.54)>.005 then raise exception 'Original source evidence was lost';end if;
end $$;
rollback;
