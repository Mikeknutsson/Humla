-- User clarification: transport stays at full price; only tipping gets 10% off.
do $patch$
declare definition text;
begin
 definition:=pg_get_functiondef('private.hub_internal_economy_rows_v1(jsonb)'::regprocedure);
 definition:=replace(definition,'round((r->>''bundle_transport'')::numeric*0.9,2)','round((r->>''bundle_transport'')::numeric,2)');
 definition:=replace(definition,'when category in(''transport'',''tipp_deponi'')then round((r->>''amount'')::numeric*0.9,2)',
  'when category=''tipp_deponi''then round((r->>''amount'')::numeric*0.9,2)
   when category=''transport''then round((r->>''amount'')::numeric,2)');
 definition:=replace(definition,'category in(''transport'',''tipp_deponi'')then 0.10','category=''tipp_deponi''then 0.10');
 definition:=replace(definition,'category in(''transport'',''tipp_deponi'')then round(debit_amount,2)-transfer_amount','category=''tipp_deponi''then round(debit_amount,2)-transfer_amount');
 definition:=replace(definition,'''Publicerad Hub-fördelning: transportdelen minus 10 %''else''Debiteringsbelopp från Workify minus 10 %''',
  '''Publicerad Hub-fördelning: transportdelen till fullt pris''when category=''tipp_deponi''then''Debiteringsbelopp från Workify minus 10 %''else''Transport: fullt debiteringsbelopp från Workify''');
 execute definition;
 definition:=pg_get_functiondef('public.hub_kpi_internal_economy_export_v1(uuid,date,date,integer[])'::regprocedure);
 definition:=replace(definition,'Transport, tipp och övriga debiterade interna tjänster värderas till 90 % av debiteringsbeloppet (10 % avdrag). Material inklusive transport följer publicerad Hub-uppdelning; transportdelen får 10 % avdrag.',
  'Transport värderas till fullt debiteringsbelopp. Tipp/deponi värderas till 90 % av debiteringsbeloppet (10 % avdrag). Material inklusive transport följer publicerad Hub-uppdelning; transportdelen behåller fullt pris.');
 execute definition;
end $patch$;
notify pgrst,'reload schema';
