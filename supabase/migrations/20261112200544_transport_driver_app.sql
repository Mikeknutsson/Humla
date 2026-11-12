-- Driver access uses confirmed, time-valid canonical person links. No preview impersonation.
insert into public.hub_role_permissions(role,permission_code) values('worker','transport.assignments.read') on conflict do nothing;
create function private.transport_driver_person(p_tenant uuid) returns uuid language plpgsql stable security definer set search_path='' as $$
declare p uuid;n integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'transport.assignments.read') then raise exception 'permission_denied';end if;
 select count(*),(array_agg(l.person_object_id))[1] into n,p from private.hub_driver_account_links l
 join public.hub_objects o on o.id=l.person_object_id and o.tenant_id=l.tenant_id and o.object_type='Person' and o.status='active'
 where l.tenant_id=p_tenant and l.user_id=auth.uid() and l.valid_from<=now() and (l.valid_to is null or l.valid_to>now());
 if n<>1 then raise exception 'driver_link_required';end if;return p;
end $$;
revoke all on function private.transport_driver_person(uuid) from public,anon,authenticated;
create function private.transport_driver_orders(p_tenant uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p uuid;
begin
 p=private.transport_driver_person(p_tenant);
 return coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'number',o.order_number,'version',o.version,
 'title',o.payload->>'title','status',o.payload->>'status','execution',o.payload->>'execution_state',
 'start',o.payload->>'start','end',o.payload->>'end','customer',o.payload->>'customer','project',o.payload->>'project',
 'location',o.payload->>'location','instruction',o.payload->>'instruction','vehicle',o.payload->>'vehicle',
 'contactName',o.payload->>'contactName','contactPhone',o.payload->>'contactPhone','report',o.payload->'driverReport',
 'lines',(select coalesce(jsonb_agg(jsonb_build_object('id',l->>'id','label',l->>'label','quantity',l->'quantity','unit',l->>'unit')),'[]') from jsonb_array_elements(o.payload->'lines') l)) order by o.payload->>'start',o.id)
 from public.hub_transport_orders o where o.tenant_id=p_tenant and o.payload->>'driverId'=p::text),'[]');
end $$;
revoke all on function private.transport_driver_orders(uuid) from public,anon;
grant execute on function private.transport_driver_orders(uuid) to authenticated;
create function public.hub_transport_driver_orders(p_tenant uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.transport_driver_orders(p_tenant)$$;
revoke all on function public.hub_transport_driver_orders(uuid) from public,anon;
grant execute on function public.hub_transport_driver_orders(uuid) to authenticated;
create table private.transport_driver_commands(
 tenant_id uuid not null, user_id uuid not null, request_id uuid not null,
 order_id uuid not null references public.hub_transport_orders(id), action text not null, data jsonb not null,
 result_version integer not null, created_at timestamptz not null default now(),primary key(tenant_id,user_id,request_id));
alter table private.transport_driver_commands enable row level security;
revoke all on private.transport_driver_commands from public,anon,authenticated;
create function private.transport_driver_command(p_tenant uuid,p_order uuid,p_version integer,p_request uuid,p_action text,p_data jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare person uuid;o public.hub_transport_orders;prev private.transport_driver_commands;v_payload jsonb;k text;v numeric;report jsonb;
begin
 person=private.transport_driver_person(p_tenant);
 if p_request is null or p_action not in ('start','pause','resume','report','complete') or p_action is null or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>10000 then raise exception 'invalid_command';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant::text||':orderportal-planning',0));
 select * into o from public.hub_transport_orders where id=p_order and tenant_id=p_tenant for update;
 if not found or o.payload->>'driverId' is distinct from person::text then raise exception 'order_not_assigned';end if;
 select * into prev from private.transport_driver_commands where tenant_id=p_tenant and user_id=auth.uid() and request_id=p_request;
 if found then
 if prev.order_id<>p_order or prev.action<>p_action or prev.data<>p_data then raise exception 'request_reused';end if;return prev.result_version;end if;
 if o.version is distinct from p_version then raise exception 'version_conflict';end if;
 if o.payload->>'status' not in ('Planerad','Pågående') then raise exception 'order_closed';end if;
 v_payload=o.payload;
 if p_action='start' then
 if v_payload->>'status'<>'Planerad' then raise exception 'invalid_transition';end if;
 v_payload=v_payload||jsonb_build_object('status','Pågående','execution_state','running','actualStart',now());
 elsif p_action in ('pause','resume') then
 if v_payload->>'status'<>'Pågående' or coalesce(v_payload->>'execution_state','running')<>(case p_action when 'pause' then 'running' else 'paused' end) then raise exception 'invalid_transition';end if;
 v_payload=v_payload||jsonb_build_object('execution_state',case p_action when 'pause' then 'paused' else 'running' end);
 elsif p_action in ('report','complete') then
 report='{}';
 foreach k in array array['hours','loads','tonnes'] loop
 if p_data?k and p_data->k<>'null'::jsonb then
 if jsonb_typeof(p_data->k)<>'number' then raise exception 'invalid_quantity';end if;v=(p_data->>k)::numeric;
 if v<0 or v>100000 or (k='loads' and v<>trunc(v)) then raise exception 'invalid_quantity';end if;
 report=report||jsonb_build_object(k,v);end if;end loop;
 if length(coalesce(p_data->>'note',''))>4000 then raise exception 'note_too_long';end if;
 report=report||jsonb_build_object('note',coalesce(p_data->>'note',''),'reportedAt',now(),'reportedBy',auth.uid());
 v_payload=v_payload||jsonb_build_object('driverReport',report);
 if p_action='complete' then
 if o.payload->>'status'<>'Pågående' then raise exception 'invalid_transition';end if;
 v_payload=v_payload||jsonb_build_object('status','Utförd','execution_state','finished','actualEnd',now());end if;
 end if;
 v_payload=v_payload||jsonb_build_object('version',o.version+1);
 update public.hub_transport_orders set payload=v_payload,version=o.version+1,updated_at=now() where id=p_order;
 insert into public.hub_transport_history(tenant_id,order_id,version,actor_id,before_data,after_data) values(p_tenant,p_order,o.version+1,auth.uid(),o.payload,v_payload);
 insert into private.transport_driver_commands(tenant_id,user_id,request_id,order_id,action,data,result_version) values(p_tenant,auth.uid(),p_request,p_order,p_action,p_data,o.version+1);
 return o.version+1;
end $$;
revoke all on function private.transport_driver_command(uuid,uuid,integer,uuid,text,jsonb) from public,anon;
grant execute on function private.transport_driver_command(uuid,uuid,integer,uuid,text,jsonb) to authenticated;
create function public.hub_transport_driver_command(p_tenant uuid,p_order uuid,p_version integer,p_request uuid,p_action text,p_data jsonb)
returns integer language sql security invoker set search_path='' as $$select private.transport_driver_command(p_tenant,p_order,p_version,p_request,p_action,p_data)$$;
revoke all on function public.hub_transport_driver_command(uuid,uuid,integer,uuid,text,jsonb) from public,anon;
grant execute on function public.hub_transport_driver_command(uuid,uuid,integer,uuid,text,jsonb) to authenticated;
