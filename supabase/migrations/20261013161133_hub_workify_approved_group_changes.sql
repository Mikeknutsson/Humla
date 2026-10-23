-- Explicit row-level approval of classification-only changes during activation.
create table private.hub_workify_approved_cost_groups (
 run_id uuid not null references private.hub_workify_activation_runs(id),
 tenant_id uuid not null,
 fact_id text not null,
 old_group text not null,
 new_group text not null,
 approved_at timestamptz not null default clock_timestamp(),
 approval_reference text not null,
 primary key(run_id,fact_id),
 check(old_group<>new_group)
);
alter table private.hub_workify_approved_cost_groups enable row level security;
revoke all on private.hub_workify_approved_cost_groups from public,anon,authenticated;

do $migration$
declare definition text; needle text; replacement text;
begin
 definition:=pg_get_functiondef('private.hub_workify_validate_approved_generation_v1(uuid,uuid)'::regprocedure);
 needle:='with old_costs as(select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=run.previous_generation and kind=''cost''),';
 replacement:=$new$with old_costs as(
 select (jsonb_populate_record(null::private.hub_kpi_prepared_facts,
 to_jsonb(o)||jsonb_build_object('business_group',coalesce(a.new_group,o.business_group)))).*
 from private.hub_kpi_prepared_facts o
 left join private.hub_workify_approved_cost_groups a
 on a.run_id=run.id and a.tenant_id=o.tenant_id and a.fact_id=o.fact_id and a.old_group=o.business_group
 where o.tenant_id=p_tenant and o.generation_id=run.previous_generation and o.kind='cost'),$new$;
 if strpos(definition,needle)=0 then raise exception 'Unexpected cost comparison';end if;
 definition:=replace(definition,needle,replacement);
 needle:='''costSplitPreserved'',true';
 if strpos(definition,needle)=0 then raise exception 'Unexpected activation result';end if;
 definition:=replace(definition,needle,$new$'costSplitPreserved',not exists(select 1 from private.hub_workify_approved_cost_groups where run_id=run.id and tenant_id=p_tenant),
 'costAmountsAndTargetsPreserved',true,
 'approvedCostGroupChanges',(select count(*) from private.hub_workify_approved_cost_groups where run_id=run.id and tenant_id=p_tenant)$new$);
 execute definition;
end $migration$;
