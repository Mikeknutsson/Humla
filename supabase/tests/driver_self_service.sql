begin;
do $$ declare t uuid; owner_user uuid; worker_user uuid; person uuid;begin
 select tenant_id,user_id into t,owner_user from public.hub_tenant_members where role='owner' and status='active' limit 1;
 select user_id into worker_user from public.hub_tenant_members where tenant_id=t and user_id<>owner_user and status='active' limit 1;
 select o.id into person from public.hub_objects o where o.tenant_id=t and o.object_type='Person' and exists(select 1 from public.hub_identity_keys k where k.tenant_id=t and k.object_id=o.id and k.identity_type='transpa_employee_id' and k.confidence=1) limit 1;
 if worker_user is null or person is null then raise exception 'Test fixtures missing';end if;
 update public.hub_tenant_members set role='worker' where tenant_id=t and user_id=worker_user;
 perform set_config('test.driver_tenant',t::text,true);perform set_config('test.driver_owner',owner_user::text,true);perform set_config('test.driver_worker',worker_user::text,true);perform set_config('test.driver_person',person::text,true);
end $$;
set local role authenticated;
do $$ declare t uuid:=current_setting('test.driver_tenant')::uuid; p uuid:=current_setting('test.driver_person')::uuid; w uuid:=current_setting('test.driver_worker')::uuid; r jsonb;begin
 perform set_config('request.jwt.claim.sub',current_setting('test.driver_owner'),true);
 r:=public.hub_driver_directory_v1(t);
 if jsonb_array_length(r->'people')=0 then raise exception 'Owner directory missing';end if;
 perform public.hub_driver_bind_account_v1(t,w,p);
 perform public.hub_driver_bind_account_v1(t,w,p); -- idempotent
 perform set_config('request.jwt.claim.sub',w::text,true);
 r:=public.hub_driver_self_v1(t,current_date-27,current_date);
 if jsonb_array_length(r->'days')<>28 then raise exception 'Expected one status per date';end if;
 if exists(select 1 from jsonb_array_elements(r->'days') d where d->>'reporting' not in ('good','attention','unknown') or d ?| array['hours','amount','employee_id']) then raise exception 'Invalid day payload';end if;
 if exists(select 1 from jsonb_array_elements(r->'vehicle_context') v where v ?| array['amount','revenue','cost','salary','hours','transactions','unit_id']) then raise exception 'Vehicle financial detail exposed';end if;
 if r->>'status'<>'ready' then raise exception 'Own report missing';end if;
 if r ?| array['revenue','cost','salary','transactions','employee_id','person_id','hours','amount'] then raise exception 'Sensitive response';end if;
 begin perform public.hub_driver_self_v1(t,current_date-27,current_date,p);raise exception 'Preview allowed to worker';exception when insufficient_privilege then null;end;
 begin perform public.hub_driver_directory_v1(t);raise exception 'Directory allowed to worker';exception when insufficient_privilege then null;end;
 begin perform public.hub_driver_bind_account_v1(t,w,p);raise exception 'Binding allowed to worker';exception when insufficient_privilege then null;end;
 begin perform public.hub_driver_self_v1(gen_random_uuid(),current_date-27,current_date);raise exception 'Cross tenant allowed';exception when insufficient_privilege then null;end;
 begin perform 1 from private.hub_driver_account_links;raise exception 'Direct link access';exception when insufficient_privilege then null;end;
 if public.hub_has_permission(t,'kpi.read') then raise exception 'Worker has financial permissions';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.driver_owner'),true);
 perform public.hub_driver_bind_account_v1(t,w,null);
 perform set_config('request.jwt.claim.sub',w::text,true);
 if public.hub_driver_self_v1(t,current_date-27,current_date)->>'status'<>'unlinked' then raise exception 'Unlink failed';end if;
end $$;
reset role;
select 'PASS: owner preview, self-only scope, cross-tenant denial, private links, no money, worker permissions, bind/unbind' as result;
rollback;
