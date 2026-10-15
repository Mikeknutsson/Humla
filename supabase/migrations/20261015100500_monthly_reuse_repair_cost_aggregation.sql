-- The repair subtotal uses the already materialized scope, avoiding a second
-- expansion of the same financial source rows within a single report period.
do $migration$
declare d text;needle text;replacement text;start_at integer;end_at integer;
begin
 d:=pg_get_functiondef('private.hub_kpi_transport_period_report_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 needle:='sum(amount) filter(where kind=''cost'' and category=''fuel'') fuel,';
 if strpos(d,needle)=0 then raise exception 'Unexpected period totals';end if;
 replacement:='sum(amount)filter(where source=''NEXT''and kind=''cost''and category=''service_repair''and account=''4630''and(concat_ws('' '',description,original->>''Verifikationstext'')ilike ''%verkstad%''or original->>''Verifikation nr''~''^AO[.][0-9]{4}-[0-9]{2}$'')) workshop_repair_debit,'||chr(10)||needle;
 d:=replace(d,needle,replacement);
 d:=replace(d,'''cost'',round(cost,2),''estimated_payroll'',','''cost'',round(cost,2),''workshop_repair_debit'',round(coalesce(workshop_repair_debit,0),2),''estimated_payroll'',');
 start_at:=strpos(d,' select round(coalesce(sum(f.amount),0),2)into workshop_debit');
 end_at:=strpos(substr(d,start_at),' output:=output||jsonb_build_object(''next_time''');
 if start_at=0 or end_at=0 then raise exception 'Unexpected repair subtotal lookup';end if;
 d:=substr(d,1,start_at-1)||' workshop_debit:=(output->>''workshop_repair_debit'')::numeric;'||chr(10)||substr(d,start_at+end_at-1);
 execute d;
end $migration$;
