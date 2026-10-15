-- Restrict snapshot evidence to selected calendar bounds while retaining the
-- exact month predicate (including non-contiguous fiscal-month selections).
do $migration$
declare d text;needle text;
begin
 d:=pg_get_functiondef('private.hub_kpi_prepared_snapshot_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 needle:='fy_from:=make_date(p_fiscal_year,9,1);fy_to:=make_date(p_fiscal_year+1,8,31);';
 if strpos(d,needle)=0 then raise exception 'Unexpected snapshot period declaration';end if;
 d:=replace(d,'fy_to date;','fy_to date;selected_from date;selected_to date;');
 d:=replace(d,needle,needle||$patch$
 select min(make_date(p_fiscal_year+case when m<9 then 1 else 0 end,m,1)),
  (max(make_date(p_fiscal_year+case when m<9 then 1 else 0 end,m,1))+interval '1 month - 1 day')::date
 into selected_from,selected_to from unnest(months)m;
$patch$);
 d:=replace(d,'and f.fiscal_year=p_fiscal_year','and f.fiscal_year=p_fiscal_year and f.occurred_on between selected_from and selected_to');
 execute d;
 -- The user removed overhead from this report. Other Hub endpoints keep it.
 d:=pg_get_functiondef('public.hub_kpi_monthly_transport_report_v1(uuid,integer,integer,text,jsonb)'::regprocedure);
 needle:='private.hub_kpi_overhead_projection_v1(p_tenant_id,p_fiscal_year,array[p_month],p_filters||case when center='''' then ''{}''::jsonb else jsonb_build_object(''cost_center'',center)end,private.hub_kpi_mapped_units_projection_v1(p_tenant_id,report))';
 if strpos(d,needle)=0 then raise exception 'Unexpected monthly report projection';end if;
 d:=replace(d,needle,'private.hub_kpi_mapped_units_projection_v1(p_tenant_id,report)');
 execute d;
end $migration$;
