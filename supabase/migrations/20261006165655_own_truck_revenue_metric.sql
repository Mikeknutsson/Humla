-- Only the per-truck metric changes. Financial totals continue to include hired vehicles.
do $patch$
declare signature text; definition text; original text;
begin
 foreach signature in array array[
 'private.hub_kpi_prepared_snapshot_v1(uuid,integer,integer[],jsonb)',
 'private.hub_kpi_month_snapshot_v1(uuid,integer,integer[],jsonb)'
 ] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  original:='''revenue_per_vehicle'',round(t.revenue/nullif(t.vehicles,0),2)';
  if strpos(definition,original)=0 then raise exception 'Unexpected truck metric in %',signature;end if;
  execute replace(definition,original,'''revenue_per_vehicle'',round((t.revenue-t.hired)/nullif(t.vehicles,0),2)');
 end loop;
 definition:=pg_get_functiondef('private.hub_kpi_cost_center_finance_v1(uuid,date,date,text)'::regprocedure);
 definition:=replace(definition,'cost,count(distinct vehicle) filter(where kind=''revenue'' and amount>0 and vehicle is not null) vehicle_count',
 'cost,coalesce(sum(amount) filter(where kind=''revenue'' and vehicle=''LASTBIL''),0) hired,count(distinct vehicle) filter(where kind=''revenue'' and amount>0 and vehicle is not null and vehicle not in (''LASTBIL'',''Ej fördelat'')) vehicle_count');
 original:='''revenue_per_vehicle'',round(revenue/nullif(vehicle_count,0),2)';
 if strpos(definition,original)=0 then raise exception 'Unexpected cost center truck metric';end if;
 execute replace(definition,original,'''revenue_per_vehicle'',round((revenue-hired)/nullif(vehicle_count,0),2)');
 definition:=pg_get_functiondef('public.hub_kpi_dashboard_display_v1(uuid,date,date,date,date)'::regprocedure);
 original:='round((hub#>>''{metrics,revenue}'')::numeric/nullif((select count(*) from jsonb_array_elements(vehicle_rows)';
 if strpos(definition,original)=0 then raise exception 'Unexpected display truck metric';end if;
 execute replace(definition,original,'round(((hub#>>''{metrics,revenue}'')::numeric-coalesce((select sum((r->>''revenue'')::numeric) from jsonb_array_elements(vehicle_rows) r where r->>''vehicle''=''LASTBIL''),0))/nullif((select count(*) from jsonb_array_elements(vehicle_rows)');
end $patch$;
