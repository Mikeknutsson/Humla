do $patch$ declare d text;begin
d:=pg_get_functiondef('private.hub_driver_vehicle_context_v1(uuid,uuid,date,date)'::regprocedure);
if strpos(d,'min(business_group)business_group')=0 then raise exception 'Goal context group hook missing';end if;
execute replace(d,'min(business_group)business_group',$new$min(business_group)filter(where kind='revenue' and business_group<>'Ej klassificerat')business_group$new$);
end $patch$;
