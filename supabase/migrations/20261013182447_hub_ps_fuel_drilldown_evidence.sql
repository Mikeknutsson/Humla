-- Fuel detail must use the same frozen, applied reconciliation as KPI totals.
-- A raw or rejected Piusi observation alone must not suppress a NEXT row.
do $migration$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_monthly_fuel_sources_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 needle:=$old$not(coalesce(description,'')='PS Olje AB' and extract(month from occurred_on)::int in(select m from piusi_periods)) include_cost$old$;
 if strpos(definition,needle)=0 then raise exception 'Unexpected fuel drilldown contract';end if;
 execute replace(definition,needle,$new$not(private.hub_ps_own_tank_source_v1(original,account) and amount=0 and original?'_humla_fuel_reconciliation') include_cost$new$);
end $migration$;
