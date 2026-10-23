-- Bound the fiscal-month read before expanding JSON evidence. EXTRACT alone
-- scanned the whole fiscal year and exceeded the authenticated request timeout.
do $migration$
declare d text;needle text:=' perform private.hub_kpi_month_scope_v1(p_year,p_months);';
begin
 d:=pg_get_functiondef('private.hub_kpi_prepared_month_facts_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 if strpos(d,needle)=0 or strpos(d,'declare generation uuid;')=0 then raise exception 'Unexpected prepared month facts implementation';end if;
 d:=replace(d,'declare generation uuid;','declare generation uuid;month_from date;month_to date;');
 d:=replace(d,needle,needle||$patch$
 select min(make_date(p_year+case when m<9 then 1 else 0 end,m,1)),
  (max(make_date(p_year+case when m<9 then 1 else 0 end,m,1))+interval '1 month - 1 day')::date
 into month_from,month_to from unnest(p_months)m;
$patch$);
 d:=replace(d,'and f.fiscal_year=p_year and extract(month from f.occurred_on)::int=any(p_months)',
  'and f.fiscal_year=p_year and f.occurred_on between month_from and month_to and extract(month from f.occurred_on)::int=any(p_months)');
 execute d;
end $migration$;
