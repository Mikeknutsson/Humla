do $migration$
declare definition text;old_filter text:=$old$r.source_data->>'Artikelnummer'='3-24'$old$;
begin
 definition:=pg_get_functiondef('public.hub_saw_activity_report_v1(uuid,date,date,uuid,uuid,integer[])'::regprocedure);
 if position(old_filter in definition)=0 then raise exception 'Expected chip article filter missing';end if;
 definition:=replace(definition,old_filter,$new$r.source_data->>'Artikelnummer' in('3-24','3-09')$new$);
 definition:=replace(definition,'select r.id,r.occurred_on,r.source_data', $new$select r.id,r.occurred_on,r.source_data->>'Artikelnamn' article_name,r.source_data$new$);
 execute definition;
end $migration$;
