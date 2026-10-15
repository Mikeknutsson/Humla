-- Missing separate approval metadata must still count as an unapproved row.
do $migration$declare d text;begin
d:=pg_get_functiondef('private.hub_kpi_next_time_period_v1(uuid,integer,integer[],jsonb)'::regprocedure);
d:=replace(d,'or r.source_data#>>''{_humla_time_approval,approved}''=''true'') approved','or coalesce(r.source_data#>>''{_humla_time_approval,approved}''=''true'',false)) approved');
execute d;
end $migration$;
