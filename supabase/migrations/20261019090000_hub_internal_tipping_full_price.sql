-- Final user correction: tipping/deposit fees also retain full debited price.
do $patch$
declare definition text;
begin
 definition:=pg_get_functiondef('private.hub_internal_economy_rows_v1(jsonb)'::regprocedure);
 if position('numeric*0.9' in definition)=0 then raise exception 'Expected tipping discount not found'; end if;
 definition:=replace(definition,'round((r->>''amount'')::numeric*0.9,2)','round((r->>''amount'')::numeric,2)');
 definition:=replace(definition,'case when category=''tipp_deponi''then 0.10 else 0 end','0');
 definition:=replace(definition,'case when category=''tipp_deponi''then round(debit_amount,2)-transfer_amount else 0 end','0');
 definition:=replace(definition,'Debiteringsbelopp från Workify minus 10 %','Tipp/deponi: fullt debiteringsbelopp från Workify');
 execute definition;
 definition:=pg_get_functiondef('public.hub_kpi_internal_economy_export_v1(uuid,date,date,integer[])'::regprocedure);
 definition:=replace(definition,'Tipp/deponi värderas till 90 % av debiteringsbeloppet (10 % avdrag).','Tipp/deponi värderas till fullt debiteringsbelopp.');
 execute definition;
end $patch$;
notify pgrst,'reload schema';
