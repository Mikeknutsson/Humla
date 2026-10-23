-- Compare typed amounts/targets, avoiding differences caused only by JSON numeric scale.
do $migration$
declare definition text; needle text; replacement text;
begin
 definition:=pg_get_functiondef('private.hub_workify_validate_approved_generation_v1(uuid,uuid)'::regprocedure);
 definition:=replace(definition,'new_cost_hash text;','new_cost_hash text; cost_changes jsonb;');
 needle:=$old$select md5(string_agg(md5(jsonb_build_array(fact_id,occurred_on,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center)::text),',' order by fact_id))
 into old_cost_hash from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=run.previous_generation and kind='cost';
 select md5(string_agg(md5(jsonb_build_array(fact_id,occurred_on,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center)::text),',' order by fact_id))
 into new_cost_hash from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and kind='cost';
 if old_cost_hash is distinct from new_cost_hash then raise exception 'Existing cost split changed during Workify activation';end if;$old$;
 replacement:=$new$with old_costs as(select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=run.previous_generation and kind='cost'),
 new_costs as(select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and kind='cost'),
 differences as(
 select coalesce(o.source,n.source) source,coalesce(o.fact_id,n.fact_id) fact_id,o.amount old_amount,n.amount new_amount,
 o.project old_project,n.project new_project,o.vehicle old_vehicle,n.vehicle new_vehicle,
 o.unit_name old_unit,n.unit_name new_unit
 from old_costs o full join new_costs n using(fact_id)
 where row(o.occurred_on,o.amount,o.category,o.project,o.vehicle,o.unit_id,o.unit_name,o.business_group,o.source,o.cost_center)
 is distinct from row(n.occurred_on,n.amount,n.category,n.project,n.vehicle,n.unit_id,n.unit_name,n.business_group,n.source,n.cost_center)
 ), totals as(
 select source,count(*) rows,sum(old_amount) old_amount,sum(new_amount) new_amount,
 count(*)filter(where old_amount is distinct from new_amount) amount_changes,
 count(*)filter(where row(old_project,old_vehicle,old_unit) is distinct from row(new_project,new_vehicle,new_unit)) target_changes
 from differences group by source
 )
 select jsonb_build_object('totals',(select jsonb_agg(to_jsonb(t))from totals t),
 'examples',(select jsonb_agg(to_jsonb(d))from(select * from differences order by source,fact_id limit 5)d))
 into cost_changes where exists(select 1 from differences);
 if cost_changes is not null then raise exception 'Existing cost split changed during Workify activation: %',cost_changes;end if;$new$;
 if strpos(definition,needle)=0 then raise exception 'Unexpected cost-preservation validation';end if;
 execute replace(definition,needle,replacement);
end $migration$;
