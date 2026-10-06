-- Preserve the dated material account classification for hired vehicle carriers.
-- 9009 identifies a carrier, not the nature of every purchase on that carrier.
do $$
declare definition text; needle text := 'when x.project_reference=''9009'' then ''hired''';
begin
 definition:=pg_get_functiondef('private.hub_kpi_financial_facts_v1(uuid,date,date)'::regprocedure);
 if position(needle in definition)=0 then raise exception 'Hired category anchor missing';end if;
 if position('when x.project_reference=''9009'' and cr.cost_category=''material''' in definition)>0 then raise exception 'Material priority already installed';end if;
 definition:=replace(definition,needle,
 'when x.project_reference=''9009'' and cr.cost_category=''material'' then ''material'' '||needle);
 execute definition;
end $$;
