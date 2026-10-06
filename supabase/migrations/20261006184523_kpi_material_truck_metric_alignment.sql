do $$ declare definition text; old_fleet text; old_value text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_transport_period_report_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 old_fleet:='fleet as(select count(*) filter(where not hired and recorded_revenue<>0) active_vehicles from vehicles)';
 old_value:='round((select coalesce(sum(invoiced_revenue),0) from vehicles where not hired)/active_vehicles,2)';
 if position(old_fleet in definition)=0 or position(old_value in definition)=0 then raise exception 'Unexpected monthly fleet metric';end if;
 definition:=replace(definition,old_fleet,
 'fleet as(select case when exists(select 1 from private.hub_kpi_material_separation_settings where tenant_id=p_tenant_id and enabled) then (select count(distinct vehicle) from facts where kind=''revenue'' and amount<>0 and vehicle not in(''LASTBIL'',''Ej fördelat'')) else count(*) filter(where not hired and recorded_revenue<>0) end active_vehicles from vehicles)');
 definition:=replace(definition,old_value,
 'round((select coalesce(sum(amount),0) from facts where kind=''revenue'' and vehicle not in(''LASTBIL'',''INHYRDLASTBIL'',''Ej fördelat'',''''))/active_vehicles,2)');
 execute definition;
end $$;
