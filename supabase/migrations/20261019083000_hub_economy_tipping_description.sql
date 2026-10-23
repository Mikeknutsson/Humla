-- Explicit tipping article names may classify an otherwise unknown report row.
-- This is report evidence, not a guessed permanent project/vehicle identity.
do $patch$
declare definition text;
begin
 definition:=pg_get_functiondef('private.hub_internal_economy_rows_v1(jsonb)'::regprocedure);
 definition:=replace(definition,'union all select r->>''category''where not coalesce((r->>''bundle'')::boolean,false)',
  'union all select case when r->>''category''=''unclassified''and r->>''description''ilike''Tippavgift%''then''tipp_deponi''else r->>''category''end where not coalesce((r->>''bundle'')::boolean,false)');
 execute definition;
end $patch$;
