do $patch$
declare definition text;original text;
begin
 original:=pg_get_functiondef('public.hub_kpi_billing_balance_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 definition:=replace(original,'''cost_center'',''group'',''unit'',''vehicle'',''project''',
  '''cost_center'',''group'',''unit'',''vehicle'',''project'',''date_from'',''date_to'',''period_mode''');
 definition:=replace(definition,'select active_generation,correction_revision into generation,revision',
  'p_filters:=private.hub_kpi_ytd_filters_v1(p_year,p_filters);
 select active_generation,correction_revision into generation,revision');
 definition:=replace(definition,'where extract(month from d)::integer=any(months)',
  'where extract(month from d)::integer=any(months)
 and(not(p_filters?''date_from'')or d::date>=(p_filters->>''date_from'')::date)
 and(not(p_filters?''date_to'')or d::date<=(p_filters->>''date_to'')::date)');
 if original=definition or position('hub_kpi_ytd_filters_v1' in definition)=0 then raise exception 'Billing YTD patch missing';end if;
 execute definition;
end $patch$;
notify pgrst,'reload schema';
