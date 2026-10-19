-- Keep the existing full-month fleet contract; add explicit daily YTD access.
do $patch$
declare definition text;
begin
 definition:=pg_get_functiondef('private.hub_fleet_kpi_v1(uuid,integer,integer[],uuid,text)'::regprocedure);
 definition:=replace(definition,'private.hub_fleet_kpi_v1(','private.hub_fleet_kpi_ytd_v1(');
 definition:=replace(definition,'today date:=(now() at time zone ''Europe/Stockholm'')::date;',
  'today date:=(private.hub_kpi_ytd_filters_v1(p_year,''{"period_mode":"ytd"}''::jsonb)->>''date_to'')::date;');
 if position('hub_kpi_ytd_filters_v1' in definition)=0 then raise exception 'Fleet YTD cutoff patch missing';end if;
 execute definition;
 definition:=pg_get_functiondef('private.hub_fleet_comparison_v1(uuid,integer,integer[],uuid,text)'::regprocedure);
 definition:=replace(definition,'private.hub_fleet_comparison_v1(','public.hub_fleet_comparison_ytd_v1(');
 definition:=replace(definition,'private.hub_fleet_kpi_v1(','private.hub_fleet_kpi_ytd_v1(');
 execute definition;
end $patch$;
revoke all on function private.hub_fleet_kpi_ytd_v1(uuid,integer,integer[],uuid,text)from public,anon,authenticated;
revoke all on function public.hub_fleet_comparison_ytd_v1(uuid,integer,integer[],uuid,text)from public,anon;
grant execute on function public.hub_fleet_comparison_ytd_v1(uuid,integer,integer[],uuid,text)to authenticated;
notify pgrst,'reload schema';
