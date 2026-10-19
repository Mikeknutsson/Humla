-- Own-produced soil must not inherit a transport sale price as its self cost.
do $patch$
declare definition text;
begin
 definition:=pg_get_functiondef('private.hub_internal_economy_rows_v1(jsonb)'::regprocedure);
 definition:=replace(definition,'select r,c.category,','select r,c.category,');
 definition:=replace(definition,'then''tipp_deponi''else r->>''category''end where not',
  'then''tipp_deponi''when r->>''description''ilike''Matjord%''then''material''else r->>''category''end where not');
 definition:=replace(definition,'case when c.category=''material''then r->''purchase''else ''{}''::jsonb end purchase',
  'case when c.category=''material''then case when r->>''description''ilike''Matjord%''then jsonb_build_object(''status'',''missing_own_material_self_cost'',''price_source'',''Fastställd självkostnad för matjord saknas. Ange kostnad per ton i Hubben.'')else r->''purchase''end else ''{}''::jsonb end purchase');
 execute definition;
end $patch$;
