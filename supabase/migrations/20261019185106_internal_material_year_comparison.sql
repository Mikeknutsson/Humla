do $migration$
declare definition text;needle text := '(''Interna intäkter'',''total'',''Fakturerat internt totalt'',''kr'',''internal''),';
begin
 definition:=pg_get_functiondef('public.hub_kpi_compare_snapshots_v1(uuid,integer[],text,jsonb,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 or strpos(definition,'material_margin.difference')>0 then raise exception 'Unexpected year comparison definition';end if;
 execute replace(definition,needle,needle||'
(''Interna intäkter'',''material_margin.billed'',''Fakturerat internpris material'',''kr'',''internal''),
(''Interna intäkter'',''material_margin.purchase_cost'',''Beräknat inköp internmaterial'',''kr'',''internal''),
(''Interna intäkter'',''material_margin.difference'',''Mellanskillnad internmaterial'',''kr'',''internal''),
(''Interna intäkter'',''material_margin.margin_percent'',''Mellanskillnad / internpris'',''%'',''internal''),');
end $migration$;
notify pgrst,'reload schema';
