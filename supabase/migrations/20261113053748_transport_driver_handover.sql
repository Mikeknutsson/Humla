-- Final handover is atomic, audited and permanently locked for the driver.
create or replace function private.transport_driver_orders(p_tenant uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p uuid;
begin
 p=private.transport_driver_person(p_tenant);
 return coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'number',o.order_number,'version',o.version,
 'title',o.payload->>'title','status',o.payload->>'status','execution',o.payload->>'execution_state',
 'start',o.payload->>'start','end',o.payload->>'end','customer',o.payload->>'customer','project',o.payload->>'project',
 'location',o.payload->>'location','instruction',o.payload->>'instruction','vehicle',o.payload->>'vehicle',
 'contactName',o.payload->>'contactName','contactPhone',o.payload->>'contactPhone','report',o.payload->'driverReport','submittedAt',o.payload->>'driverSubmittedAt',
 'lines',(select coalesce(jsonb_agg(jsonb_build_object('id',l->>'id','label',l->>'label','quantity',l->'quantity','unit',l->>'unit')),'[]') from jsonb_array_elements(o.payload->'lines') l)) order by o.payload->>'start',o.id)
 from public.hub_transport_orders o where o.tenant_id=p_tenant and o.payload->>'driverId'=p::text),'[]');
end $$;
create or replace function private.transport_driver_command(p_tenant uuid,p_order uuid,p_version integer,p_request uuid,p_action text,p_data jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare person uuid;o public.hub_transport_orders;prev private.transport_driver_commands;v_payload jsonb;k text;v numeric;report jsonb;
begin
 person=private.transport_driver_person(p_tenant);
 if p_request is null or p_action not in ('start','pause','resume','report','complete','submit') or p_action is null or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>10000 then raise exception 'invalid_command';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant::text||':orderportal-planning',0));
 select * into o from public.hub_transport_orders where id=p_order and tenant_id=p_tenant for update;
 if not found or o.payload->>'driverId' is distinct from person::text then raise exception 'order_not_assigned';end if;
 select * into prev from private.transport_driver_commands where tenant_id=p_tenant and user_id=auth.uid() and request_id=p_request;
 if found then
 if prev.order_id<>p_order or prev.action<>p_action or prev.data<>p_data then raise exception 'request_reused';end if;return prev.result_version;end if;
 if o.version is distinct from p_version then raise exception 'version_conflict';end if;
 if o.payload->>'driverSubmittedAt' is not null or coalesce(o.payload->>'status','') not in ('Planerad','Pågående','Utförd') then raise exception 'order_closed';end if;
 v_payload=o.payload;
 if p_action='start' then
 if v_payload->>'status'<>'Planerad' then raise exception 'invalid_transition';end if;
 v_payload=v_payload||jsonb_build_object('status','Pågående','execution_state','running','actualStart',now());
 elsif p_action in ('pause','resume') then
 if v_payload->>'status'<>'Pågående' or coalesce(v_payload->>'execution_state','running')<>(case p_action when 'pause' then 'running' else 'paused' end) then raise exception 'invalid_transition';end if;
 v_payload=v_payload||jsonb_build_object('execution_state',case p_action when 'pause' then 'paused' else 'running' end);
 elsif p_action in ('report','complete','submit') then
 report='{}';
 foreach k in array array['hours','loads','tonnes'] loop
 if p_data?k and p_data->k<>'null'::jsonb then
 if jsonb_typeof(p_data->k)<>'number' then raise exception 'invalid_quantity';end if;v=(p_data->>k)::numeric;
 if v<0 or v>100000 or (k='loads' and v<>trunc(v)) then raise exception 'invalid_quantity';end if;
 report=report||jsonb_build_object(k,v);end if;end loop;
 if length(coalesce(p_data->>'note',''))>4000 then raise exception 'note_too_long';end if;
 report=report||jsonb_build_object('note',coalesce(p_data->>'note',''),'savedAt',now(),'savedBy',auth.uid());
 v_payload=v_payload||jsonb_build_object('driverReport',report);
 if p_action='submit' then
 if o.payload->>'status'<>'Utförd' then raise exception 'invalid_transition';end if;
 v_payload=v_payload||jsonb_build_object('status','Rapporterad','driverSubmittedAt',now(),'driverSubmittedBy',auth.uid());
 end if;
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
create or replace function private.transport_save(p_tenant_id uuid,p_id uuid,p_expected_version integer,p_request_id uuid,p_payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_old public.hub_transport_orders;v_payload jsonb;v_amount numeric;v_ref uuid;v_key text;v_type text;v_line jsonb;v_number text;v_version integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'transport.orders.manage') then raise exception 'permission_denied'; end if;
 if exists(select 1 from jsonb_array_elements(coalesce(p_payload->'lines','[]')) l where nullif(l->>'priceRuleId','') is not null or nullif(l->>'pickupSiteId','') is not null or nullif(l->>'deliverySiteId','') is not null) then raise exception 'test_price_reference_not_allowed';end if;
 if p_request_id is null or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>250000 then raise exception 'invalid_payload';end if;
 if coalesce(p_payload->>'title','')='' or nullif(p_payload->>'customerId','') is null then raise exception 'customer_title_required';end if;
 if coalesce(p_payload->>'status','') not in ('Utkast','Planerad','Pågående','Utförd','Rapporterad','Faktureringsklar','Avbruten') then raise exception 'invalid_status';end if;
 if coalesce(p_payload->>'start','') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$' or coalesce(p_payload->>'end','') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$' or (p_payload->>'end')::timestamp <= (p_payload->>'start')::timestamp then raise exception 'invalid_dates';end if;
 foreach v_key in array array['customerId','projectId','vehicleId','driverId'] loop
 v_ref=nullif(p_payload->>v_key,'')::uuid;
 if v_ref is not null then
 v_type=case v_key when 'customerId' then 'Customer' when 'projectId' then 'Project' when 'vehicleId' then 'Vehicle' else 'Person' end;
 if not exists(select 1 from public.hub_objects where id=v_ref and tenant_id=p_tenant_id and lower(object_type)=lower(v_type) and status='active') then raise exception 'invalid_canonical_reference';end if;
 end if;
 end loop;
 if jsonb_typeof(p_payload->'lines') is distinct from 'array' or jsonb_array_length(p_payload->'lines')>200 then raise exception 'invalid_lines';end if;
 v_amount=0;
 for v_line in select value from jsonb_array_elements(p_payload->'lines') loop
 if coalesce(v_line->>'label','')='' or coalesce(v_line->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' or jsonb_typeof(v_line->'quantity') is distinct from 'number' or jsonb_typeof(v_line->'price') is distinct from 'number' or (v_line->>'quantity')::numeric<0 or (v_line->>'price')::numeric<0 then raise exception 'invalid_line';end if;
 perform (v_line->>'date')::date;
 v_amount=v_amount+round((v_line->>'quantity')::numeric*(v_line->>'price')::numeric,2);
 end loop;
 if p_payload->>'status'='Faktureringsklar' and jsonb_array_length(p_payload->'lines')=0 then raise exception 'lines_required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':orderportal-planning',0));
 if p_payload->>'status' in ('Utkast','Planerad','Pågående') then
 if private.orderportal_maintenance_overlap(p_tenant_id,p_payload->>'vehicleId',p_payload->>'start',p_payload->>'end') then raise exception 'maintenance_conflict';end if;
 if exists(select 1 from public.hub_transport_orders o where o.tenant_id=p_tenant_id and o.id is distinct from p_id and (p_id is not null or o.request_id<>p_request_id) and o.payload->>'status' in ('Utkast','Planerad','Pågående') and o.payload->>'start'<p_payload->>'end' and p_payload->>'start'<o.payload->>'end' and ((nullif(p_payload->>'vehicleId','') is not null and o.payload->>'vehicleId'=p_payload->>'vehicleId') or (nullif(p_payload->>'driverId','') is not null and o.payload->>'driverId'=p_payload->>'driverId'))) then raise exception 'resource_conflict';end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||p_request_id::text,0));
 if p_id is null then
 select id into v_id from public.hub_transport_orders where tenant_id=p_tenant_id and request_id=p_request_id;
 if found then return v_id;end if;
 v_id=gen_random_uuid();insert into private.transport_order_counters(tenant_id,last_number) values(p_tenant_id,1) on conflict(tenant_id) do update set last_number=private.transport_order_counters.last_number+1 returning 'H-'||lpad(last_number::text,8,'0') into v_number;v_version=1;
 insert into public.hub_objects(id,tenant_id,object_type,data,source_of_truth) values(v_id,p_tenant_id,'TransportOrder',jsonb_build_object('is_test',false,'display_name',v_number),'humla_transport');
 else
 select * into v_old from public.hub_transport_orders where id=p_id and tenant_id=p_tenant_id for update;
 if not found then raise exception 'order_not_found';end if;
 if v_old.version is distinct from p_expected_version then raise exception 'version_conflict';end if;
 v_id=v_old.id;v_number=v_old.order_number;v_version=v_old.version+1;
 end if;
 v_payload=p_payload||jsonb_build_object('id',v_id,'number',v_number,'source','humla','version',v_version,'amount',v_amount,'is_test',false,'issues','[]'::jsonb);
 -- Driver execution and submission evidence are server-owned and survive manager edits.
 v_payload=(v_payload-array['driverReport','driverSubmittedAt','driverSubmittedBy','execution_state','actualStart','actualEnd'])||coalesce((select jsonb_object_agg(key,value) from jsonb_each(coalesce(v_old.payload,'{}')) where key=any(array['driverReport','driverSubmittedAt','driverSubmittedBy','execution_state','actualStart','actualEnd'])),'{}');
 -- Recalculate every line server-side. Never accept client-computed totals.
 v_payload=jsonb_set(v_payload,'{lines}',coalesce((select jsonb_agg(value||jsonb_build_object('amount',round((value->>'quantity')::numeric*(value->>'price')::numeric,2),'valid',true,'errors','[]'::jsonb)) from jsonb_array_elements(p_payload->'lines')),'[]'::jsonb));
 if p_id is null then
 insert into public.hub_transport_orders(id,tenant_id,request_id,order_number,payload,amount,created_by) values(v_id,p_tenant_id,p_request_id,v_number,v_payload,v_amount,auth.uid());
 else
 update public.hub_transport_orders set payload=v_payload,amount=v_amount,version=v_version,updated_at=now() where id=v_id;
 end if;
 insert into public.hub_transport_history(tenant_id,order_id,version,actor_id,before_data,after_data) values(p_tenant_id,v_id,v_version,auth.uid(),v_old.payload,v_payload);
 return v_id;
end $$;
