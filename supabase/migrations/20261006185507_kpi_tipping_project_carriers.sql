-- Preserve the confirmed destination project. Attach its existing project unit
-- only when the tenant has explicitly enabled material/tipping separation.
do $$ declare definition text; needle text; routing text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_separate_material_v1(uuid,uuid)'::regprocedure);
 needle:=' -- Only detach material purchases from vehicle carriers.';
 if position(needle in definition)=0 then raise exception 'Unexpected separation function';end if;
 routing:=$route$
 with destinations as (
 select t.fact_id,case when count(distinct u.id)=1 then (array_agg(distinct u.id))[1] end id,
 case when count(distinct u.id)=1 then max(u.name) end name
 from private.hub_kpi_prepared_facts t join public.kpi_units u
 on u.tenant_id=p_tenant and u.enabled and u.unit_type='project' and t.project=any(u.projects)
 and u.valid_from<=t.occurred_on and (u.valid_to is null or u.valid_to>=t.occurred_on)
 where t.generation_id=p_generation and t.occurred_on>=cfg.valid_from and t.category='tipp_deponi'
 and (t.unit_id is null or t.vehicle is not null)
 group by t.fact_id
 )
 update private.hub_kpi_prepared_facts t set unit_id=d.id,unit_name=d.name,vehicle=null,
 original=t.original||jsonb_build_object('_humla_material_separation',jsonb_build_object(
 'method','tipping_destination_project','original_fact_id',t.fact_id,'original_amount',t.amount,
 'original_vehicle',t.vehicle,'original_unit_id',t.unit_id,'original_project',t.project))
 from destinations d where t.generation_id=p_generation and t.fact_id=d.fact_id and d.id is not null;
 $route$;
 execute replace(definition,needle,routing||needle);
end $$;
