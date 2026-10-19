do $patch$
declare definition text;
begin
 definition:=pg_get_functiondef('public.hub_kpi_internal_economy_export_v1(uuid,date,date,integer[])'::regprocedure);
 definition:=replace(definition,'prices jsonb;rows jsonb;result jsonb;','prices jsonb;export_rows jsonb;result jsonb;');
 definition:=replace(definition,'rows:=private.hub_internal_economy_rows_v1(source_rows);','export_rows:=private.hub_internal_economy_rows_v1(source_rows);');
 definition:=replace(definition,'jsonb_array_elements(rows)r','jsonb_array_elements(export_rows)r');
 definition:=replace(definition,'''generation'',generation,''rows'',rows,''totals''','''generation'',generation,''rows'',export_rows,''totals''');
 execute definition;
end $patch$;
