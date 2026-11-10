-- The API queues the report refresh after the file transaction commits.
do $migration$
declare
 definition text:=pg_get_functiondef('private.hub_stena_upload_v1(uuid,text,text,text,jsonb,text,jsonb,boolean)'::regprocedure);
 queue_call constant text:=' perform public.hub_kpi_request_report_sync_v1(p_tenant);';
begin
 if strpos(definition,queue_call)=0 then
  raise exception 'Expected Stena upload refresh call is missing';
 end if;
 definition:=replace(definition,queue_call,'');
 definition:=replace(definition,',''sync_requested'',true','');
 execute definition;
end $migration$;

-- PostgREST applies the timeout from the exposed RPC at request start.
alter function public.hub_stena_upload_v1(uuid,text,text,text,jsonb,text,jsonb,boolean)
 set statement_timeout='60s';
