-- Source report flags are not a test of financial validity. Reuse confirmed
-- account rules and immutable external document evidence, not guessed vehicles.
do $migration$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('private.hub_next_completeness_rows_v1(uuid)'::regprocedure);
 needle:=$old$when lower(source_data->>'Inkludera i rapporter') is distinct from 'true' then 'source_policy_review'$old$;
 if strpos(definition,needle)=0 then raise exception 'Unexpected source-flag classifier';end if;
 definition:=replace(definition,needle,'');
 needle:=$old$or nullif(trim(source_data->>'Leverantör'),'') is null
 or source_data->>'Leverantör' ~* 'elleholms' or account='4015'$old$;
 if strpos(definition,needle)=0 then raise exception 'Unexpected external-document classifier';end if;
 definition:=replace(definition,needle,$new$or (nullif(trim(source_data->>'Leverantör'),'') is null
 and coalesce(source_data->>'Verifikationstext','') !~ '^Levfakt .+ \([0-9]+\)$')
 or coalesce(source_data->>'Leverantör','') ~* 'elleholms'
 or coalesce(source_data->>'Verifikationstext','') ~* 'elleholms' or account in('4015','7010')$new$);
 execute definition;
end $migration$;
