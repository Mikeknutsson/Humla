-- Serialize native test-order writes per tenant before checking shared resources.
-- Workify imports are deliberately excluded: their planning metadata is incomplete.
do $patch$
declare d text;
begin
 d=pg_get_functiondef('private.orderportal_save_priced(uuid,uuid,integer,uuid,jsonb)'::regprocedure);
 d=replace(d, 'for v_line in select value from jsonb_array_elements(p_payload->''lines'') loop', $guard$
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':orderportal-planning',0));
 if p_payload->>'status' in ('Utkast','Planerad','Pågående') and exists(
 select 1 from public.hub_orderportal_orders o where o.tenant_id=p_tenant_id and o.id is distinct from p_id
 and o.payload->>'status' in ('Utkast','Planerad','Pågående')
 and (o.payload->>'start')::timestamp < (p_payload->>'end')::timestamp and (p_payload->>'start')::timestamp < (o.payload->>'end')::timestamp
 and ((nullif(p_payload->>'vehicleId','') is not null and o.payload->>'vehicleId'=p_payload->>'vehicleId') or (nullif(p_payload->>'driverId','') is not null and o.payload->>'driverId'=p_payload->>'driverId'))
 -- An idempotent create retry must return its existing order, not conflict with itself.
 and (p_id is not null or o.request_id is distinct from p_request_id)
 ) then raise exception 'resource_conflict';end if;
 for v_line in select value from jsonb_array_elements(p_payload->'lines') loop$guard$);
 execute d;
end $patch$;
create function private.orderportal_plan(p_tenant_id uuid,p_id uuid,p_version integer,p_start text,p_end text,p_vehicle uuid,p_driver uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare o public.hub_orderportal_orders;payload jsonb;v_label text='';d_label text='';
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'permission_denied';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':orderportal-planning',0));
 select * into o from public.hub_orderportal_orders where id=p_id and tenant_id=p_tenant_id for update;
 if not found then raise exception 'order_not_found';end if;
 if o.version is distinct from p_version then raise exception 'version_conflict';end if;
 if o.payload->>'status' not in ('Utkast','Planerad','Pågående') then raise exception 'order_not_plannable';end if;
 if p_vehicle is not null then
 select coalesce(data->>'display_name',data->>'registration_number',data->>'name',id::text) into v_label from public.hub_objects where tenant_id=p_tenant_id and id=p_vehicle and lower(object_type)='vehicle' and status='active';
 if not found then raise exception 'invalid_resource';end if;
 end if;
 if p_driver is not null then
 select coalesce(data->>'display_name',data->>'name',id::text) into d_label from public.hub_objects where tenant_id=p_tenant_id and id=p_driver and object_type='Person' and status='active';
 if not found then raise exception 'invalid_resource';end if;
 end if;
 payload=o.payload||jsonb_build_object('start',p_start,'end',p_end,'vehicleId',coalesce(p_vehicle::text,''),'vehicle',v_label,'driverId',coalesce(p_driver::text,''),'driver',d_label);
 -- Article dates/prices are not rewritten by a scheduling change.
 return private.orderportal_save_priced(p_tenant_id,o.id,p_version,o.request_id,payload);
end $$;
revoke all on function private.orderportal_plan(uuid,uuid,integer,text,text,uuid,uuid) from public,anon;
grant execute on function private.orderportal_plan(uuid,uuid,integer,text,text,uuid,uuid) to authenticated;
create function public.hub_orderportal_plan(p_tenant_id uuid,p_id uuid,p_version integer,p_start text,p_end text,p_vehicle uuid,p_driver uuid)
returns uuid language sql security invoker set search_path='' as $$select private.orderportal_plan(p_tenant_id,p_id,p_version,p_start,p_end,p_vehicle,p_driver)$$;
revoke all on function public.hub_orderportal_plan(uuid,uuid,integer,text,text,uuid,uuid) from public,anon;
grant execute on function public.hub_orderportal_plan(uuid,uuid,integer,text,text,uuid,uuid) to authenticated;
