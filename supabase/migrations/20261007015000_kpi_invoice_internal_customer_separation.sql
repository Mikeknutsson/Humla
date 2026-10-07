-- Customer classification and both averages belong to Hub, not React.
-- Covers Elleholms Maskin AB, Elleholms Maskin (STENA), and service labels.
-- Other Elleholms customers are not classified as internal by this rule.
do $$ declare definition text; needle text; begin
 definition:=pg_get_functiondef('private.hub_kpi_invoice_lead_time_v1(uuid,integer,integer[],jsonb,integer)'::regprocedure);
 needle:='max(customer_name) customer_name,';
 if position(needle in definition)=0 then raise exception 'Invoice customer aggregation changed';end if;
 definition:=replace(definition,needle,needle||'bool_or(coalesce(customer_name,'''')~*''elleholms[[:space:]]+maskin'') is_internal,');
 needle:='''average_days'',round(avg(days_to_invoice) filter(where days_to_invoice>0),2),''averaged_order_days'',count(*) filter(where days_to_invoice>0),';
 if position(needle in definition)=0 then raise exception 'Invoice average changed';end if;
 definition:=replace(definition,needle,'''average_days'',round(avg(days_to_invoice) filter(where days_to_invoice>0 and not is_internal),2),''averaged_order_days'',count(*) filter(where days_to_invoice>0 and not is_internal),''internal_average_days'',round(avg(days_to_invoice) filter(where days_to_invoice>0 and is_internal),2),''internal_averaged_order_days'',count(*) filter(where days_to_invoice>0 and is_internal),''internal_order_days'',count(*) filter(where is_internal),');
 definition:=replace(definition,'Ofakturerade utesluts. Orderdagar','Ofakturerade utesluts. Elleholms Maskin som kund räknas som internöverföring och redovisas separat från huvudsnittet. Orderdagar');
 execute definition;
end $$;
