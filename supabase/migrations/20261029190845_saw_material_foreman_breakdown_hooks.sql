do $patch$
declare d text;
begin
 d:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 if strpos(d,'perform private.hub_saw_material_value_v1')=0 then
 if strpos(d,'perform private.hub_apply_monthly_overhead_v1(job.tenant_id,generation);')=0 then raise exception 'Worker hook missing';end if;
 d:=replace(d,'perform private.hub_apply_monthly_overhead_v1(job.tenant_id,generation);','perform private.hub_apply_monthly_overhead_v1(job.tenant_id,generation);'||chr(10)||'perform private.hub_saw_material_value_v1(job.tenant_id,generation);');execute d;
 end if;
end $patch$;


do $patch$ declare d text;begin
d:=pg_get_functiondef('public.hub_transport_leader_scorecard_v4(uuid,date,date,uuid,uuid,integer,integer[],text)'::regprocedure);
if strpos(d,'''saw_breakdown''')>0 then raise exception 'Already patched';end if;
d:=replace(d,$old$ 'generation',(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant),$old$,$new$ 'saw_breakdown',(select case when count(*)>0 then jsonb_build_object(
 'revenue',coalesce(sum(amount)filter(where kind='revenue'),0),
 'material_revenue',coalesce(sum(amount)filter(where kind='revenue' and original?'_humla_saw_chip'),0),
 'material_tons',coalesce(sum((original#>>'{_humla_saw_chip,tons}')::numeric)filter(where kind='revenue' and original?'_humla_saw_chip'),0),
 'material_rate',(select chip_rate_per_ton from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant),
 'cost',coalesce(sum(amount)filter(where kind='cost'),0),
 'management_cost',coalesce(sum(amount)filter(where kind='cost' and category='management'),0),
 'other_cost',coalesce(sum(amount)filter(where kind='cost' and category is distinct from 'management'),0),
 'truck_charge',coalesce(sum((original#>>'{_humla_saw_activity,hours}')::numeric*(original#>>'{_humla_saw_activity,truck_hour_rate}')::numeric)
 filter(where kind='revenue' and original#>>'{_humla_saw_activity,reason}'='article_hour_split' and original#>>'{_humla_saw_activity,branch}'='saw'),0),
 'material_rows',coalesce(jsonb_agg(jsonb_build_object('id',fact_id,'date',occurred_on,'tons',original#>'{_humla_saw_chip,tons}',
 'amount',amount,'source',original#>>'{_humla_saw_chip,source}','ticket',original#>>'{_humla_saw_chip,ticket_number}',
 'order',coalesce(original#>>'{_humla_saw_chip,order_number}',original#>>'{_humla_saw_chip,order_numbers}')) order by occurred_on,fact_id)
 filter(where kind='revenue' and original?'_humla_saw_chip'),'[]'::jsonb)) end
 from facts where unit_id=(select unit_id from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant)),
 'generation',(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant),$new$);execute d;
d:=pg_get_functiondef('public.hub_saw_activity_report_v1(uuid,date,date,uuid,uuid,integer[])'::regprocedure);
d:=replace(d,$old$where d.original?'_humla_saw_activity' or$old$,$new$where exists(select 1 from private.hub_saw_activity_rules_v1 sr where sr.tenant_id=p_tenant and sr.unit_id=d.unit_id) or d.original?'_humla_saw_activity' or$new$);
d:=replace(d,$old$(evidence#>>'{_humla_saw_activity,branch}'='saw' or evidence?'_humla_monthly_overhead')$old$,$new$unit_id=(select unit_id from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant)$new$);execute d;
end $patch$;