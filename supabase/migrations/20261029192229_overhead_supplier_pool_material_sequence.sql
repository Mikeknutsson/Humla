do $patch$ declare d text;n text;begin
d:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
n:='perform private.hub_saw_material_value_v1(job.tenant_id,generation);'||chr(10)||'perform private.hub_apply_monthly_overhead_v1(job.tenant_id,generation);';
if strpos(d,n)=0 then raise exception 'Worker hook missing';end if;
execute replace(d,n,'perform private.hub_saw_material_value_v1(job.tenant_id,generation);'||chr(10)||'perform private.hub_allocate_saw_supplier_common_v1(job.tenant_id,generation);'||chr(10)||'perform private.hub_apply_monthly_overhead_v1(job.tenant_id,generation);');
end $patch$;