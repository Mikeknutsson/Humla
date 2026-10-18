-- Generic evidence must respect the same explicit exclusions as report routing.
do $migration$declare d text;begin
 d:=pg_get_functiondef('private.hub_match_scores_v2(uuid)'::regprocedure);
 d:=replace(d,'where e.run_id=p_run and','where o.data->>''report_fallback''is distinct from''unresolved''and not exists(select 1 from private.hub_kpi_project_exclusions x where x.tenant_id=r.tenant_id and x.enabled and x.economic_unit_id=o.id)and e.run_id=p_run and');
 execute d;
end $migration$;
