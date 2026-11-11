begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $test$
declare t uuid='944597b6-9c46-4bef-998d-f19e23c4245b'; c uuid; oid uuid; req uuid=gen_random_uuid(); p jsonb; n integer; blocked boolean=false;
begin
select id into c from public.hub_objects where tenant_id=t and object_type='Customer' limit 1;
p=jsonb_build_object('title','Automatiskt rollback-test','customerId',c,'status','Utkast','start','2026-10-01T07:00','end','2026-10-01T09:00','lines',jsonb_build_array(jsonb_build_object('label','Test','date','2026-10-01','quantity',2,'price',100,'amount',99999)));
oid=public.hub_orderportal_save(t,null,0,req,p);
if (select amount from public.hub_orderportal_orders where id=oid)<>200 then raise exception 'amount mismatch';end if;
if public.hub_orderportal_save(t,null,0,req,p)<>oid then raise exception 'idempotency failure';end if;
perform public.hub_orderportal_save(t,oid,1,req,p||'{"status":"Utförd"}'::jsonb);
if (select count(*) from public.hub_orderportal_history where order_id=oid)<>2 then raise exception 'audit mismatch';end if;
begin perform public.hub_orderportal_save(t,oid,1,req,p);exception when others then if sqlerrm='version_conflict' then blocked=true;else raise;end if;end;
if not blocked then raise exception 'concurrency failure';end if;
blocked=false;
begin perform public.hub_orderportal_save(t,oid,2,req,p||'{"status":"Fakturerad"}'::jsonb);exception when others then if sqlerrm='invalid_status' then blocked=true;else raise;end if;end;
if not blocked then raise exception 'billing guard failure';end if;
if jsonb_array_length(public.hub_orderportal_imports(t))<1111 then raise exception 'import truncated';end if;
perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
if exists(select 1 from public.hub_orderportal_orders) then raise exception 'RLS failed';end if;
if public.hub_orderportal_imports(t)<>'[]'::jsonb then raise exception 'import RLS failed';end if;
blocked=false;
begin perform public.hub_orderportal_save(t,null,0,gen_random_uuid(),p);exception when others then if sqlerrm='permission_denied' then blocked=true;else raise;end if;end;
if not blocked then raise exception 'write auth failed';end if;
end $test$;
rollback;
select 'PASS: atomic create/update, canonical identity, totals, idempotency, audit, optimistic locking, billing guard, tenant RLS, unauthorized write; all test writes rolled back' result;
