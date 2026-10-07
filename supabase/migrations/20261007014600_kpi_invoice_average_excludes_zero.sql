-- Zero-day invoices remain visible as evidence but do not dilute the average.
do $$ declare definition text; needle text; begin
 definition:=pg_get_functiondef('private.hub_kpi_invoice_lead_time_v1(uuid,integer,integer[],jsonb,integer)'::regprocedure);
 needle:='''average_days'',round(avg(days_to_invoice),2),';
 if position(needle in definition)=0 then raise exception 'Invoice average contract changed';end if;
 definition:=replace(definition,needle,'''average_days'',round(avg(days_to_invoice) filter(where days_to_invoice>0),2),''averaged_order_days'',count(*) filter(where days_to_invoice>0),''zero_order_days'',count(*) filter(where days_to_invoice=0),');
 definition:=replace(definition,'Ofakturerade utesluts. Ogiltiga','Ofakturerade utesluts. Orderdagar med 0 dagar visas i underlaget men ingår inte i snittet. Ogiltiga');
 execute definition;
end $$;
