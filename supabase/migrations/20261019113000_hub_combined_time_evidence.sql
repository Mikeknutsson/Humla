-- Retain TransPA evidence columns in the merged fleet; NEXT-only rows get a stable key.
do $patch$
declare d text;name text;
begin
 d:=pg_get_functiondef('private.hub_kpi_worked_time_projection_v1(jsonb,jsonb,numeric)'::regprocedure);
 d:=replace(d,'max((v->>''available_hours'')::numeric)capacity','max((v->>''available_hours'')::numeric)capacity,(array_agg(v))[1]metadata');
 d:=replace(d,'coalesce(e.hours,0)next_hours','coalesce(e.hours,0)next_hours,n.metadata');
 d:=replace(d,'''vehicle'',vehicle,''hours'',hours', '''vehicle_id'',coalesce(metadata->>''vehicle_id'',vehicle),''time_reports'',metadata->''time_reports'',''vehicle'',vehicle,''hours'',hours');
 execute d;
 foreach name in array array['public.hub_kpi_monthly_transport_report_v1','private.hub_kpi_monthly_transport_report_base_v1']loop
  d:=pg_get_functiondef((name||'(uuid,integer,integer,text,jsonb)')::regprocedure);
  d:=replace(d,'Rapporterad TransPA-tid','Arbetad fordonstid från TransPA + NEXT');
  execute d;
 end loop;
end $patch$;
notify pgrst,'reload schema';
