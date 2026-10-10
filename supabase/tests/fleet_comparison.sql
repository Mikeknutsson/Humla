begin;
set local request.jwt.claim.sub='5a6fa4c4-5427-47fa-9835-d997fe81c7d5';
do $$
declare fixture jsonb; r jsonb; assets uuid[]; g uuid; t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';
begin
 select jsonb_agg(jsonb_build_object('id',n::text,'meter_type','odometer_km','missing_months',0,'usage',1000,'cost_per_unit',case when n=4 then 140 else 100 end,'fuel_per_unit',10,'service_repair',100)) into fixture from generate_series(1,4) n;
 r:=private.hub_fleet_compare_rows_v1(fixture,'["1","2","3","4"]');
 if r#>>'{3,metrics,cost_per_unit,outlier}'<>'true' or (r#>>'{3,metrics,cost_per_unit,median}')::numeric<>100 or (r#>>'{3,metrics,cost_per_unit,change_pct}')::numeric<>40 then raise exception 'Median/outlier failed';end if;
 r:=private.hub_fleet_compare_rows_v1(fixture,'["1","2","4"]');
 if exists(select 1 from jsonb_array_elements(r) a where a#>>'{metrics,cost_per_unit,outlier}'='true' or a#>>'{metrics,cost_per_unit,median}' is not null) then raise exception 'Thin group flagged';end if;
 fixture:=jsonb_set(fixture,'{0,missing_months}','1');fixture:=jsonb_set(fixture,'{1,meter_type}','"engine_hours"');
 r:=private.hub_fleet_compare_rows_v1(fixture,'["1","2","3","4"]');
 if r#>>'{0,metrics,cost_per_unit,value}' is not null or r#>>'{3,metrics,cost_per_unit,peers}'<>'1' then raise exception 'Mixed units/incomplete measurement included';end if;
 select array_agg(id) into assets from(select id from public.hub_objects where tenant_id=t and object_type='Vehicle' and data->>'vehicle_type'='Lastbil' and public.hub_resolve_canonical_object_v1(t,id)=id limit 4)x;
 g:=public.hub_fleet_comparison_save_v1(t,null,'Rollback test','Lastbil',assets,'test');
 perform public.hub_fleet_comparison_save_v1(t,g,'Rollback revised','Lastbil',assets,'test',1);
 if (select count(*) from public.hub_object_versions where object_id=g)<>2 then raise exception 'History missing';end if;
 begin perform public.hub_fleet_comparison_save_v1(t,g,'stale','Lastbil',assets,'test',1);raise exception 'Stale edit accepted';exception when raise_exception then if sqlerrm='Stale edit accepted' then raise;end if;end;
 begin perform public.hub_fleet_comparison_save_v1(t,null,'Mixed','Personbil',assets,'test');raise exception 'Mixed categories accepted';exception when raise_exception then if sqlerrm='Mixed categories accepted' then raise;end if;end;
 r:=public.hub_fleet_comparison_v1(t,2025,array[9,10,11,12,1,2,3,4,5,6,7,8]);
 if jsonb_array_length(r->'comparison_groups')<1 then raise exception 'Group missing from report';end if;
 if (r#>>'{summary,cost}')::numeric<>24084764.37 then raise exception 'Existing cost changed';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 begin perform public.hub_fleet_comparison_v1(t,2025,array[11]);raise exception 'Unauthorized read accepted';exception when insufficient_privilege then null;end;
 begin perform public.hub_fleet_comparison_save_v1(t,null,'unauthorized','Lastbil',assets,'test');raise exception 'Unauthorized write accepted';exception when insufficient_privilege then null;end;
end $$;
rollback;
