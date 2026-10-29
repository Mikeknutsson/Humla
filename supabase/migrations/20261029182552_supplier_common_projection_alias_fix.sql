do $migration$
declare d text;
begin
select pg_get_functiondef('private.hub_allocate_saw_supplier_common_v1(uuid,uuid)'::regprocedure)into d;
d:=replace(d,$old$delete from private.hub_kpi_prepared_display_facts d using private.hub_kpi_prepared_facts f
where f.tenant_id=p_tenant and f.generation_id=p_generation and f.original#>>'{_humla_saw_activity,reason}'='supplier_work_full'and d.tenant_id=f.tenant_id and d.generation_id=f.generation_id and d.fact_id=f.fact_id;$old$,$new$delete from private.hub_kpi_prepared_display_facts d using private.hub_kpi_prepared_facts ff
where ff.tenant_id=p_tenant and ff.generation_id=p_generation and ff.original#>>'{_humla_saw_activity,reason}'='supplier_work_full'and d.tenant_id=ff.tenant_id and d.generation_id=ff.generation_id and d.fact_id=ff.fact_id;$new$);
execute d;
end $migration$;