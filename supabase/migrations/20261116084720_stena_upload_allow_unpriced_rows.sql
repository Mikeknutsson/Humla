-- Retain rows with a missing price for review without replacing a known amount.
do $migration$
declare
 definition text;
 signature regprocedure;
 required_price constant text := ' or (p_kind=''history'' and price is null) or (p_kind=''settled'' and settled_amount is null)';
 old_priority constant text := 'order by r.revenue_object_id,(f.source_kind=''settled'')desc,f.uploaded_at desc,f.file_hash';
 new_priority constant text := 'order by r.revenue_object_id,(r.amount is not null)desc,(f.source_kind=''settled'')desc,f.uploaded_at desc,f.file_hash';
begin
 definition := pg_get_functiondef('private.hub_stena_upload_v1(uuid,text,text,text,jsonb,text,jsonb,boolean)'::regprocedure);
 if strpos(definition,required_price)=0 then raise exception 'Expected Stena price check is missing'; end if;
 execute replace(definition,required_price,'');
 foreach signature in array array[
  'private.hub_apply_stena_priority_v1(uuid,uuid)'::regprocedure,
  'private.hub_payment_outcome_source_v1(uuid,date)'::regprocedure
 ] loop
  definition := pg_get_functiondef(signature);
  if strpos(definition,old_priority)=0 then raise exception 'Expected Stena source priority is missing in %', signature; end if;
  execute replace(definition,old_priority,new_priority);
 end loop;
end
$migration$;
