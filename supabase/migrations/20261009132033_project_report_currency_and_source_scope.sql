-- Round allocated Hub amounts once to currency precision and preserve indexed import lookup.
do $$
declare definition text;
begin
 definition:=pg_catalog.pg_get_functiondef('private.hub_kpi_project_report_v3(uuid,date,date,text,text,uuid,integer,text,text[])'::regprocedure);
 if position('f.occurred_on date,f.kind,f.amount,null::text account' in definition)=0 then raise exception 'Expected Hub evidence projection missing';end if;
 definition:=replace(definition,'f.occurred_on date,f.kind,f.amount,null::text account','f.occurred_on date,f.kind,round(f.amount,2) amount,null::text account');
 definition:=replace(definition,'where f.tenant_id=p_tenant_id and f.occurred_on between p_from and p_to','where f.tenant_id=p_tenant_id and f.occurred_on between p_from and p_to and exists(select 1 from selected scope where scope.cost_center=f.cost_center)');
 definition:=replace(definition,'r.id::text=f.fact_id','r.id=case when f.fact_id ~* ''^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'' then f.fact_id::uuid end');
 execute definition;
end $$;
notify pgrst,'reload schema';
