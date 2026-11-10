do $fix$ declare d text; begin
 d:=pg_get_functiondef('public.hub_transport_leader_scorecard_v4(uuid,date,date,uuid,uuid,integer,integer[],text)'::regprocedure);
 if strpos(d,'when not ola_view then')=0 then raise exception 'Missing Transport grouping condition'; end if;
 execute replace(d,'when not ola_view then','when ola_view is not true then');
end $fix$;