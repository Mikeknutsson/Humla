-- Explain approved historical replacements alongside the existing source rules.
do $migration$declare d text;begin
d:=pg_get_functiondef('private.hub_kpi_transport_period_report_v1(uuid,integer,integer[],jsonb)'::regprocedure);
d:=replace(d,'Registrerade intäkter minus NEXT-kostnader och TransPA-schablon. Bränsledelen ersätts','Registrerade intäkter minus NEXT-kostnader, TransPA-schablon och godkända NEXT-schabloner efter avräkning av motsvarande arbetskostnad. Bränsledelen ersätts');
execute d;
d:=pg_get_functiondef('private.hub_kpi_next_time_period_v1(uuid,integer,integer[],jsonb)'::regprocedure);
d:=replace(d,'Historisk arbetstid saknar rolluppgift','Historik 2025/26: 33 000 kr i månadslön enligt godkänd schablon, endast tid utöver TransPA kostnadssätts. Motsvarande NEXT-arbetskostnad räknas av inom projekt/månad; ej täckt kostnad ligger kvar. Historisk arbetstid saknar rolluppgift');
execute d;
end $migration$;
