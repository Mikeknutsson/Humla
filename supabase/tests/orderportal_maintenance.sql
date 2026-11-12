begin;
-- All synthetic bookings and changes below roll back.
do $test$
declare t uuid='944597b6-9c46-4bef-998d-f19e23c4245b';c uuid;v uuid;ext text;oid uuid;ver integer;r jsonb;res jsonb;count_before bigint;
begin
 select connection_id into c from private.orderportal_maintenance_sync where tenant_id=t;
 select e.object_id,e.external_id into v,ext from public.hub_external_references e join public.hub_objects o on o.id=e.object_id where e.connection_id=c and e.external_type='FordonskontrollVehicle' and o.status='active' limit 1;
 r=jsonb_build_object('id','QA-maintenance-rollback','number','QA-MAINTENANCE','title','QA service','start','2099-10-01T07:00:00Z','end','2099-10-01T09:00:00Z','source',jsonb_build_object('id',ext,'type','vehicle'));
 res=public.hub_sync_fordonskontroll_entities(t,c,'WorkOrder','FordonskontrollWorkOrder',jsonb_build_array(r));
 if (res->>'failed')::int<>0 then raise exception 'fixture import';end if;
 select object_id into oid from public.hub_external_references where connection_id=c and external_type='FordonskontrollWorkOrder' and external_id='QA-maintenance-rollback';
 select version into ver from public.hub_objects where id=oid;
 perform public.hub_sync_fordonskontroll_entities(t,c,'WorkOrder','FordonskontrollWorkOrder',jsonb_build_array(r));
 if (select version from public.hub_objects where id=oid)<>ver then raise exception 'unchanged sync created history';end if;
 perform public.hub_sync_fordonskontroll_entities(t,c,'WorkOrder','FordonskontrollWorkOrder',jsonb_build_array(r||'{"location":"Updated workshop"}'));
 if (select version from public.hub_objects where id=oid)<>ver+1 then raise exception 'update not audited';end if;
 if (select count(*) from public.hub_external_references where connection_id=c and external_type='FordonskontrollWorkOrder' and external_id='QA-maintenance-rollback')<>1 then raise exception 'duplicate identity';end if;
 update private.orderportal_maintenance_sync set source_ids=source_ids||'"QA-maintenance-rollback"'::jsonb where connection_id=c;
 if not private.orderportal_maintenance_overlap(t,v::text,'2099-10-01T10:00','2099-10-01T12:00') then raise exception 'Stockholm overlap';end if;
 if private.orderportal_maintenance_overlap(t,v::text,'2099-10-01T11:00','2099-10-01T12:00') then raise exception 'adjacent interval incorrectly blocked';end if;
 if private.orderportal_maintenance_overlap(gen_random_uuid(),v::text,'2099-10-01T10:00','2099-10-01T12:00') then raise exception 'tenant isolation';end if;
 perform set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
 res=public.hub_orderportal_maintenance(t);
 if not exists(select 1 from jsonb_array_elements(res->'orders') x where x->>'id'=oid::text and x->>'vehicleId'=v::text and x->>'missing'='false') then raise exception 'canonical projection';end if;
 begin
  perform public.hub_orderportal_save(t,null,0,gen_random_uuid(),jsonb_build_object('title','QA blocked','customerId',(select id from hub_objects where tenant_id=t and object_type='Customer' and status='active' limit 1),'status','Planerad','start','2099-10-01T10:00','end','2099-10-01T12:00','vehicleId',v,'lines','[]'::jsonb));
  raise exception 'save was not blocked';
 exception when others then if sqlerrm<>'maintenance_conflict' then raise;end if;end;
 update private.orderportal_maintenance_sync set source_ids=source_ids-'QA-maintenance-rollback' where connection_id=c;
 res=public.hub_orderportal_maintenance(t);
 if not exists(select 1 from jsonb_array_elements(res->'orders') x where x->>'id'=oid::text and x->>'missing'='true') then raise exception 'source disappearance hidden';end if;
 if private.orderportal_maintenance_overlap(t,v::text,'2099-10-01T10:00','2099-10-01T12:00') then raise exception 'missing source still blocks';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 begin perform public.hub_orderportal_maintenance(t);raise exception 'unauthorized read allowed';exception when others then if sqlerrm<>'permission_denied' then raise;end if;end;
 if has_function_privilege('anon','public.hub_orderportal_maintenance(uuid)','execute') or has_function_privilege('authenticated','private.orderportal_maintenance_tick()','execute') then raise exception 'unsafe grants';end if;
end $test$;
rollback;
select 'PASS: replay identity/history, updates, canonical vehicles, Stockholm overlaps, adjacency, server save guard, missing-source review, tenant permissions, grants; all fixture changes rolled back.' result;
