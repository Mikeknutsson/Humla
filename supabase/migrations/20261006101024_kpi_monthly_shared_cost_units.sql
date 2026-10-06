do $patch$ declare d text; begin
 select pg_get_functiondef(oid) into d from pg_proc where proname='hub_kpi_monthly_fuel_sources_v1' and pronamespace='private'::regnamespace;
 d:=replace(d,'select f.*,c.center,c.business_group,','select f.*,c.center,c.business_group,u.unit_id,coalesce(u.unit_id::text,''vehicle:''||f.reg) unit_key,');
 d:=replace(d,')) c on true),', ')) c on true left join lateral(select case when count(distinct u.unit_id)=1 then min(u.unit_id::text)::uuid end unit_id from private.hub_kpi_prepared_kpi_unit_periods u where u.generation_id=generation and u.tenant_id=p_tenant_id and u.valid_from<=f.dt and (u.valid_to is null or u.valid_to>=f.dt) and coalesce((u.payload->>''enabled'')::boolean,false) and u.payload->''registrations''?f.reg) u on true),');
 if position('u on true' in d)=0 then raise exception 'Fuel mapping extension failed';end if;
 d:=replace(d,'data->>''product_name'' product from scoped','data->>''product_name'' product,unit_key from scoped');
 d:=replace(d,'coalesce(original->>''Kontobeskrivning'',description) from next_fuel','coalesce(original->>''Kontobeskrivning'',description),coalesce(unit_id::text,''vehicle:''||vehicle,''unassigned'') from next_fuel');
 d:=replace(d,'''transactions'',coalesce(','''units'',coalesce((select jsonb_agg(x) from(select unit_key,round(sum(amount),2) fuel,round(sum(liters),2) liters from combined group by unit_key)x),''[]''::jsonb),''transactions'',coalesce(');
 execute d;
 select pg_get_functiondef(oid) into d from pg_proc where proname='hub_kpi_transport_period_report_v1' and pronamespace='private'::regnamespace;
 d:=replace(d,'vehicles jsonb;','vehicles jsonb; economic_units jsonb;');
 d:=replace(d,'output:=output||jsonb_build_object(''fuel_sources''', 'select coalesce(jsonb_agg(u||jsonb_build_object(''fuel'',coalesce((f->>''fuel'')::numeric,0),''fuel_liters'',(f->>''liters'')::numeric,''cost'',(u->>''cost'')::numeric-coalesce((u#>>''{cost_categories,fuel}'')::numeric,0)+coalesce((f->>''fuel'')::numeric,0)) order by u->>''label''),''[]''::jsonb) into economic_units from jsonb_array_elements(operations->''economic_units'') u left join jsonb_array_elements(fuel_report->''units'') f on f->>''unit_key''=u->>''key'';
 output:=output||jsonb_build_object(''economic_units'',economic_units,''fuel_sources''');
 execute d;
end $patch$;
