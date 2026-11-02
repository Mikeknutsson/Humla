begin;
do $$declare t uuid;u uuid;begin
 select tenant_id,user_id into t,u from public.hub_tenant_members where role='owner' and status='active' limit 1;
 perform set_config('test.stena_tenant',t::text,true);perform set_config('request.jwt.claim.sub',u::text,true);
end $$;
set local role authenticated;
do $$declare t uuid:=current_setting('test.stena_tenant')::uuid;r jsonb;rows jsonb:='[{"row_number":2,"booking":"99999887","date":"2026-10-01","registration":"","settled_amount":123.45}]';h text:='9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';begin
 r:=public.hub_stena_upload_v1(t,h,'test.xlsx','settled',rows,'dGVzdA==','{}',false);
 if (r->>'total')::numeric<>123.45 then raise exception 'Settled amount changed';end if;
 r:=public.hub_stena_upload_v1(t,h,'test.xlsx','settled',rows,'dGVzdA==','{}',true);
 if not (r->>'imported')::boolean then raise exception 'Not imported';end if;
 r:=public.hub_stena_upload_v1(t,h,'test.xlsx','settled',rows,'dGVzdA==','{}',true);
 if not (r->>'duplicate')::boolean then raise exception 'Duplicate not blocked';end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.hub_stena_upload_v1(t,h,'test.xlsx','settled',rows,'dGVzdA==','{}',false);raise exception 'Unauthorized import allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: preview amounts, atomic file ingestion, repeat-file protection and authorization; all changes rolled back' result;
rollback;
