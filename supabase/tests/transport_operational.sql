begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
insert into hub_member_permission_overrides(tenant_id,user_id,permission_code,allowed) values('944597b6-9c46-4bef-998d-f19e23c4245b','5a6fa4c4-5427-47fa-9835-d997fe81c7d5','transport.orders.manage',true) on conflict(tenant_id,user_id,permission_code) do update set allowed=true;
do $$
declare t uuid='944597b6-9c46-4bef-998d-f19e23c4245b';r uuid=gen_random_uuid();a uuid;p jsonb;
begin
 p=jsonb_build_object('title','Rollback driftorder','customerId',(select id from hub_objects where tenant_id=t and object_type='Customer' and status='active' limit 1),'status','Planerad','start','2099-01-01T07:00','end','2099-01-01T09:00','lines','[]'::jsonb);
 a=public.hub_transport_save(t,null,0,r,p);
 if a<>public.hub_transport_save(t,null,0,r,p) then raise exception 'idempotency failed';end if;
 if not exists(select 1 from hub_transport_orders where id=a and not is_test and order_number like 'H-%') then raise exception 'operational identity failed';end if;
 if exists(select 1 from hub_orderportal_orders where id=a) then raise exception 'test contamination';end if;
 perform public.hub_transport_save(t,a,1,r,p||'{"title":"Updated"}');
 if (select count(*) from hub_transport_history where order_id=a)<>2 then raise exception 'audit failed';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 begin perform public.hub_transport_save(t,null,0,gen_random_uuid(),p);raise exception 'permission bypass';exception when others then if sqlerrm<>'permission_denied' then raise;end if;end;
end $$;
rollback;
select 'PASS operational identity, numbering, idempotency, separate test data, audit and permission guard; rolled back' result;
