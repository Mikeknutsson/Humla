-- Daily YTD uses Stockholm's calendar date, including historical comparisons.
create function private.hub_kpi_ytd_filters_v1(p_year integer,p_filters jsonb,p_today date default (now()at time zone 'Europe/Stockholm')::date)
returns jsonb language plpgsql stable set search_path='' as $$
declare current_year integer;target_year integer;cutoff date;result jsonb:=p_filters-'period_mode';
begin
 if p_filters->>'period_mode' is distinct from 'ytd'then return result;end if;
 current_year:=extract(year from p_today)::int-case when extract(month from p_today)<9 then 1 else 0 end;
 if p_year>current_year then raise exception 'YTD cannot select a future fiscal year';end if;
 target_year:=p_year+case when extract(month from p_today)<9 then 1 else 0 end;
 cutoff:=make_date(target_year,extract(month from p_today)::int,1);
 cutoff:=cutoff+least(extract(day from p_today)::int,extract(day from(cutoff+interval '1 month - 1 day'))::int)-1;
 return result||jsonb_build_object('date_from',greatest(make_date(p_year,9,1),nullif(result->>'date_from','')::date),
  'date_to',least(cutoff,nullif(result->>'date_to','')::date));
end$$;
revoke all on function private.hub_kpi_ytd_filters_v1(integer,jsonb,date)from public,anon,authenticated;

do $patch$
declare definition text;original text;name text;
begin
 -- Normalize before looking up cached reports: the date is part of the cache key.
 original:=pg_get_functiondef('public.hub_kpi_overview_months_v1(uuid,integer,integer[],text,jsonb)'::regprocedure);
 definition:=replace(original,'months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);',
  'p_filters:=private.hub_kpi_ytd_filters_v1(p_fiscal_year,p_filters);
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);');
 if original=definition then raise exception 'Overview YTD patch point missing';end if;execute definition;

 -- Capacity and worked time must use the same cutoff as financial facts.
 original:=pg_get_functiondef('private.hub_kpi_prepared_snapshot_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 definition:=replace(original,'fy_from:=make_date(p_fiscal_year,9,1);fy_to:=make_date(p_fiscal_year+1,8,31);',
  'fy_from:=greatest(make_date(p_fiscal_year,9,1),nullif(p_filters->>''date_from'','''')::date);
 fy_to:=least(make_date(p_fiscal_year+1,8,31),nullif(p_filters->>''date_to'','''')::date);');
 definition:=replace(definition,'p_filters=''{}''::jsonb','(p_filters-array[''date_from'',''date_to''])=''{}''::jsonb');
 if original=definition then raise exception 'Snapshot YTD patch point missing';end if;execute definition;

 original:=pg_get_functiondef('private.hub_kpi_prepared_comparison_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 definition:=replace(original,'''from'',make_date(p_fiscal_year,9,1),''to'',make_date(p_fiscal_year+1,8,31)',
  '''from'',greatest(make_date(p_fiscal_year,9,1),nullif(p_filters->>''date_from'','''')::date),''to'',least(make_date(p_fiscal_year+1,8,31),nullif(p_filters->>''date_to'','''')::date)');
 if original=definition then raise exception 'Comparison YTD patch point missing';end if;execute definition;

 original:=pg_get_functiondef('private.hub_kpi_next_time_period_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 definition:=replace(original,'r.occurred_on between make_date(p_year,9,1)and make_date(p_year+1,8,31)',
  'r.occurred_on between greatest(make_date(p_year,9,1),nullif(p_filters->>''date_from'','''')::date)and least(make_date(p_year+1,8,31),nullif(p_filters->>''date_to'','''')::date)');
 if original=definition then raise exception 'NEXT time YTD patch point missing';end if;execute definition;

 original:=pg_get_functiondef('private.hub_kpi_monthly_fuel_sources_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 definition:=replace(original,'between make_date(p_year,9,1) and make_date(p_year+1,8,31)',
  'between greatest(make_date(p_year,9,1),nullif(p_filters->>''date_from'','''')::date) and least(make_date(p_year+1,8,31),nullif(p_filters->>''date_to'','''')::date)');
 if original=definition then raise exception 'Fuel YTD patch point missing';end if;execute definition;

 -- Verified monthly overhead cannot be presented as exact daily cost.
 original:=pg_get_functiondef('public.hub_overhead_period_v1(uuid,integer,integer[],jsonb,numeric)'::regprocedure);
 definition:=replace(original,'unsupported:=p_filters ?| array[''group'',''unit'',''vehicle'',''project''];',
  'unsupported:=p_filters ?| array[''group'',''unit'',''vehicle'',''project'']
   or (p_filters?''date_to'' and (p_filters->>''date_to'')::date<>(date_trunc(''month'',(p_filters->>''date_to'')::date)+interval ''1 month - 1 day'')::date)
   or (p_filters?''date_from'' and extract(day from(p_filters->>''date_from'')::date)<>1);');
 definition:=replace(definition,'group by f.source_row_id)',
  'and(not(p_filters?''date_from'')or f.occurred_on>=(p_filters->>''date_from'')::date)
 and(not(p_filters?''date_to'')or f.occurred_on<=(p_filters->>''date_to'')::date)
 group by f.source_row_id)');
 definition:=replace(definition,'Overheadunderlaget gäller kostnadsställen. Fördelning till vald grupp eller enhet är inte verifierad.',
  'Overheadunderlaget gäller hela månader och kostnadsställen. Kostnaden för ett delmånadsurval eller vald enhet är inte verifierad.');
 if original=definition then raise exception 'Overhead YTD patch point missing';end if;execute definition;

 -- Monthly exports share the same dates, including their previous-year requests.
 foreach name in array array['public.hub_kpi_monthly_transport_report_v1','private.hub_kpi_monthly_transport_report_base_v1']loop
  original:=pg_get_functiondef((name||'(uuid,integer,integer,text,jsonb)')::regprocedure);
  definition:=replace(original,'''group'',''unit'',''vehicle'',''project''','''group'',''unit'',''vehicle'',''project'',''date_from'',''date_to'',''period_mode''');
  if name like 'public.%'then
   definition:=replace(definition,'if length(center)>100 then',
    'p_filters:=private.hub_kpi_ytd_filters_v1(p_fiscal_year,p_filters);
 if length(center)>100 then');
  else
   definition:=replace(definition,'''to'',(report_date+interval ''1 month - 1 day'')::date',
    '''to'',least((report_date+interval ''1 month - 1 day'')::date,nullif(p_filters->>''date_to'','''')::date)');
  end if;
  if original=definition then raise exception 'Monthly YTD patch point missing: %',name;end if;execute definition;
 end loop;
end $patch$;
notify pgrst,'reload schema';
