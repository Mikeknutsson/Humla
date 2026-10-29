do $migration$
declare definition text;
begin
select pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure)into definition;
if position('hub_apply_stena_priority_v1'in definition)=0 then
if position('phase:=''hub_publish_approved_time_costs_v1'''in definition)=0 then raise exception 'Stena hook anchor missing';end if;
definition:=replace(definition,'phase:=''hub_publish_approved_time_costs_v1''','perform private.hub_apply_stena_priority_v1(job.tenant_id,generation);'||chr(10)||'phase:=''hub_publish_approved_time_costs_v1''');
execute definition;
end if;
end $migration$;