-- Preserve direct yard cost sharing and honor the dated general overhead exclusion.
do $migration$
declare
 definition text := pg_get_functiondef('private.hub_apply_yard_saw_share_v1(uuid,uuid)'::regprocedure);
 anchor constant text := 'and not(original?''_humla_yard_saw_share'')';
begin
 if strpos(definition,anchor)=0 then raise exception 'Unexpected yard-to-saw allocation definition'; end if;
 execute replace(definition,anchor,anchor||$guard$
 and (source is distinct from 'Overhead' or not exists(
  select 1 from private.hub_overhead_unit_exclusions_v1 x
  where x.tenant_id=p_tenant and x.unit_id=saw and x.cost_center='30'
   and x.valid_from<=hub_kpi_prepared_facts.occurred_on
 ))
$guard$);
end
$migration$;
