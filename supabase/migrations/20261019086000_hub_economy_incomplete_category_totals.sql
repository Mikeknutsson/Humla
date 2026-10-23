-- A missing material valuation must remain missing in project/center subtotals.
do $patch$
declare definition text;
begin
 definition:=pg_get_functiondef('public.hub_kpi_internal_economy_export_v1(uuid,date,date,integer[])'::regprocedure);
 definition:=replace(definition,'coalesce(sum(amount)filter(where r->>''category''=''material''),0)material',
  'case when count(*)filter(where r->>''category''=''material''and amount is null)=0 then coalesce(sum(amount)filter(where r->>''category''=''material''),0)end material');
 execute definition;
end $patch$;
