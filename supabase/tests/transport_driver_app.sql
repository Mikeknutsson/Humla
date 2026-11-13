begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
insert into public.hub_member_permission_overrides(tenant_id,user_id,permission_code,allowed)
select '944597b6-9c46-4bef-998d-f19e23c4245b','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',p,true from unnest(array['transport.assignments.read','transport.orders.manage'])p
on conflict(tenant_id,user_id,permission_code) do update set allowed=true;
do $$
declare t uuid='944597b6-9c46-4bef-998d-f19e23c4245b';person uuid=gen_random_uuid();oid uuid;req uuid=gen_random_uuid();p jsonb;v integer;result jsonb;action text;
begin
 insert into public.hub_objects(id,tenant_id,object_type,status,data,source_of_truth) values(person,t,'Person','active','{"display_name":"QA driver rollback"}','humla');
 update private.hub_driver_account_links set valid_to=now() where tenant_id=t and user_id=auth.uid() and (valid_to is null or valid_to>now());
 insert into private.hub_driver_account_links(tenant_id,user_id,person_object_id,valid_from,confirmed_by) values(t,auth.uid(),person,now()-interval '1 second',auth.uid());
 p=jsonb_build_object('title','QA driver','customerId',(select id from public.hub_objects where tenant_id=t and object_type='Customer' and status='active' limit 1),'status','Planerad','start','2099-01-01T07:00','end','2099-01-01T09:00','driverId',person,'internalNote','SECRET internal','lines',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'date','2099-01-01','label','QA article','quantity',2,'price',999,'purchasePrice',400,'unit','Tim')));
 oid=public.hub_transport_save(t,null,0,gen_random_uuid(),p);
 result=public.hub_transport_driver_orders(t);
 if jsonb_array_length(result)<>1 or result::text like '%SECRET%' or result::text like '%price%' or result::text like '%amount%' then raise exception 'projection leaks or wrong assignments';end if;
 v=public.hub_transport_driver_command(t,oid,1,req,'start','{}');
 if v<>2 or public.hub_transport_driver_command(t,oid,1,req,'start','{}')<>2 then raise exception 'idempotency failed';end if;
 begin perform public.hub_transport_driver_command(t,oid,2,req,'pause','{}');raise exception 'reused key allowed';exception when others then if sqlerrm<>'request_reused' then raise;end if;end;
 begin perform public.hub_transport_driver_command(t,oid,1,gen_random_uuid(),'pause','{}');raise exception 'stale version allowed';exception when others then if sqlerrm<>'version_conflict' then raise;end if;end;
 v=public.hub_transport_driver_command(t,oid,2,gen_random_uuid(),'pause','{}');
 v=public.hub_transport_driver_command(t,oid,3,gen_random_uuid(),'resume','{}');
 begin perform public.hub_transport_driver_command(t,oid,4,gen_random_uuid(),'report','{"loads":1.5}');raise exception 'fractional load accepted';exception when others then if sqlerrm<>'invalid_quantity' then raise;end if;end;
 v=public.hub_transport_driver_command(t,oid,4,gen_random_uuid(),'report','{"hours":2,"loads":3,"tonnes":50,"note":"QA"}');
 v=public.hub_transport_driver_command(t,oid,5,gen_random_uuid(),'complete','{"hours":2,"loads":3,"tonnes":50,"note":"Done"}');
 if (select amount from public.hub_transport_orders where id=oid)<>1998 or (select payload#>>'{lines,0,price}' from public.hub_transport_orders where id=oid)<>'999' then raise exception 'driver changed financials';end if;
 if (select payload->>'status' from public.hub_transport_orders where id=oid)<>'Utförd' or (select count(*) from public.hub_transport_history where order_id=oid)<>6 then raise exception 'completion audit failed';end if;
 -- Completed work remains editable until the explicit final handover.
 v=public.hub_transport_driver_command(t,oid,6,gen_random_uuid(),'report','{"hours":2.5,"note":"Corrected draft"}');
 if v<>7 then raise exception 'completed draft not editable';end if;
 req=gen_random_uuid();
 v=public.hub_transport_driver_command(t,oid,7,req,'submit','{"hours":2.5,"note":"Final report"}');
 if v<>8 or public.hub_transport_driver_command(t,oid,7,req,'submit','{"hours":2.5,"note":"Final report"}')<>8 then raise exception 'submission replay failed';end if;
 select payload into p from public.hub_transport_orders where id=oid;
 if p->>'status'<>'Rapporterad' or p->>'driverSubmittedAt' is null or p->>'driverSubmittedBy'<>auth.uid()::text then raise exception 'handover missing';end if;
 if (select count(*) from public.hub_transport_history where order_id=oid)<>8 then raise exception 'handover audit duplicated';end if;
 foreach action in array array['start','pause','resume','report','complete','submit'] loop
 begin perform public.hub_transport_driver_command(t,oid,8,gen_random_uuid(),action,'{}');raise exception 'submitted order writable';exception when others then if sqlerrm<>'order_closed' then raise;end if;end;
 end loop;
 -- Exercise the exact management queue predicate under authenticated RLS.
 execute 'set local role authenticated';
 if (select count(*) from public.hub_transport_orders where tenant_id=t and payload->>'driverSubmittedAt' is not null)<>1 then raise exception 'manager queue missing report';end if;
 execute 'reset role';
 update public.hub_member_permission_overrides set allowed=false where tenant_id=t and user_id=auth.uid() and permission_code='transport.orders.manage';
 execute 'set local role authenticated';
 if exists(select 1 from public.hub_transport_orders where tenant_id=t and payload->>'driverSubmittedAt' is not null) then raise exception 'driver can read manager queue';end if;
 execute 'reset role';
 update public.hub_member_permission_overrides set allowed=true where tenant_id=t and user_id=auth.uid() and permission_code='transport.orders.manage';
 -- Generic management save cannot erase the submission or replace driver evidence.
 perform public.hub_transport_save(t,oid,8,gen_random_uuid(),(p-array['driverSubmittedAt','driverSubmittedBy','driverReport'])||'{"status":"Utförd"}');
 if (select payload->>'driverSubmittedAt' from public.hub_transport_orders where id=oid) is null then raise exception 'manager removed lock';end if;
 begin perform public.hub_transport_driver_command(t,oid,9,gen_random_uuid(),'report','{}');raise exception 'manager status reopened driver edits';exception when others then if sqlerrm<>'order_closed' then raise;end if;end;
 if (public.hub_transport_driver_orders(t)->0->>'submittedAt') is null then raise exception 'driver lock not projected';end if;
 update public.hub_transport_orders set payload=payload||'{"driverId":""}' where id=oid;
 if jsonb_array_length(public.hub_transport_driver_orders(t))<>0 then raise exception 'reassigned order visible';end if;
 begin perform public.hub_transport_driver_command(t,oid,6,gen_random_uuid(),'report','{}');raise exception 'reassigned order writable';exception when others then if sqlerrm<>'order_not_assigned' then raise;end if;end;
 update private.hub_driver_account_links set valid_to=now() where tenant_id=t and user_id=auth.uid() and valid_to is null;
 begin perform public.hub_transport_driver_orders(t);raise exception 'expired link allowed';exception when others then if sqlerrm<>'driver_link_required' then raise;end if;end;
 begin perform public.hub_transport_driver_orders(gen_random_uuid());raise exception 'other tenant allowed';exception when others then if sqlerrm<>'permission_denied' then raise;end if;end;
 if has_function_privilege('anon','public.hub_transport_driver_orders(uuid)','execute') or has_table_privilege('authenticated','private.transport_driver_commands','select') then raise exception 'unsafe grants';end if;
end $$;
rollback;
select 'PASS: own assignments, safe projection, start/pause/resume/report/complete/submit, permanent lock, manager preservation, replay, version conflict, immutable prices, audit, reassignment, expired link, tenant isolation and grants. Rolled back.' result;
