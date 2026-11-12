-- Read-only upstream polling. Existing Hub identities and object history remain authoritative.
create table private.orderportal_maintenance_sync (
 connection_id uuid primary key references public.hub_connections(id),
 tenant_id uuid not null references public.hub_tenants(id),
 request_id bigint, cursor text, records jsonb not null default '[]', pages integer not null default 0,
 started_at timestamptz, last_success_at timestamptz, next_at timestamptz not null default now(),
 last_error text, source_ids jsonb not null default '[]'
);
alter table private.orderportal_maintenance_sync enable row level security;
revoke all on private.orderportal_maintenance_sync from public,anon,authenticated;

create function private.orderportal_maintenance_tick() returns void
language plpgsql security definer set search_path='' as $$
declare j record; r record; payload jsonb; credentials jsonb; next_cursor text; result jsonb;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('orderportal-maintenance-poll',0)) then return; end if;
 for j in select s.* from private.orderportal_maintenance_sync s join public.hub_connections c on c.id=s.connection_id
 where c.connector_type='fordonskontrollen' and c.status in ('active','error') and s.next_at<=now()
 and not exists(select 1 from public.hub_connection_sync_settings x where x.connection_id=c.id and not x.enabled)
 for update of s loop
 begin
  if j.request_id is not null then
   select * into r from net._http_response where id=j.request_id;
   if not found then
    if j.started_at<now()-interval '20 minutes' then raise exception 'API request expired'; end if;
    continue;
   end if;
   if r.status_code is distinct from 200 or r.error_msg is not null then raise exception 'Fordonskontrollen HTTP %',r.status_code;end if;
   payload:=r.content::jsonb;
   if jsonb_typeof(payload->'data') is distinct from 'array' then raise exception 'Unexpected workorders response';end if;
   next_cursor:=nullif(payload->>'next_cursor','');
   if next_cursor is not null and next_cursor=j.cursor then raise exception 'Repeated pagination cursor';end if;
   j.records:=j.records||(payload->'data');j.pages:=j.pages+1;
   if j.pages>100 then raise exception 'Workorders pagination limit reached';end if;
   if next_cursor is null then
    -- The whole snapshot is imported atomically; partial failures keep the previous snapshot.
    perform pg_advisory_xact_lock(hashtextextended(j.tenant_id::text||':orderportal-planning',0));
    result:=public.hub_sync_fordonskontroll_entities(j.tenant_id,j.connection_id,'WorkOrder','FordonskontrollWorkOrder',j.records);
    if coalesce((result->>'failed')::integer,0)>0 then raise exception 'Workorder import failed validation';end if;
    update private.orderportal_maintenance_sync set request_id=null,cursor=null,records='[]',pages=0,
     source_ids=coalesce((select jsonb_agg(v->>'id') from jsonb_array_elements(j.records) v),'[]'),
     last_success_at=now(),last_error=null,next_at=now()+interval '15 minutes'
    where connection_id=j.connection_id;
    continue;
   end if;
   j.cursor:=next_cursor;
  else
   j.records:='[]';j.pages:=0;j.cursor:=null;j.started_at:=now();
  end if;
  credentials:=public.hub_get_connection_credentials(j.tenant_id,j.connection_id);
  if coalesce(credentials->>'api_token','')='' then raise exception 'API credentials unavailable';end if;
  j.request_id:=net.http_get(
   url:='https://fordonskontroll.app/external/api/fleet_manager/v1/workorders',
   params:=jsonb_strip_nulls(jsonb_build_object('per_page','100','cursor',j.cursor)),
   headers:=jsonb_strip_nulls(jsonb_build_object('Accept','application/json','Authorization','Bearer '||(credentials->>'api_token'),'X-TOKEN-SECRET',nullif(credentials->>'api_secret',''))),
   timeout_milliseconds:=25000);
  update private.orderportal_maintenance_sync set request_id=j.request_id,cursor=j.cursor,records=j.records,pages=j.pages,started_at=j.started_at,next_at=now() where connection_id=j.connection_id;
 exception when others then
  update private.orderportal_maintenance_sync set request_id=null,cursor=null,records='[]',pages=0,last_error=left(sqlerrm,300),next_at=now()+interval '15 minutes' where connection_id=j.connection_id;
 end;
 end loop;
end $$;
revoke all on function private.orderportal_maintenance_tick() from public,anon,authenticated;

create function private.orderportal_maintenance(p_tenant_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'permission_denied';end if;
 return jsonb_build_object(
 'sync',(select coalesce(jsonb_agg(jsonb_build_object('lastSuccess',last_success_at,'error',last_error,'running',request_id is not null)),'[]') from private.orderportal_maintenance_sync where tenant_id=p_tenant_id),
 'orders',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'version',o.version,'updatedAt',o.updated_at,'raw',o.data->'fordonskontroll','vehicleId',v.id,'vehicle',v.data->>'registration_number','missing',not (s.source_ids ? e.external_id))),'[]')
 from public.hub_objects o join public.hub_external_references e on e.object_id=o.id and e.tenant_id=p_tenant_id and e.external_type='FordonskontrollWorkOrder'
 join private.orderportal_maintenance_sync s on s.connection_id=e.connection_id and s.tenant_id=p_tenant_id and s.last_success_at is not null
 left join public.hub_objects v on v.id::text=o.data->>'source_object_id' and v.tenant_id=p_tenant_id and v.object_type in ('Vehicle','vehicle') and v.status='active'
 where o.tenant_id=p_tenant_id and o.object_type='WorkOrder' and o.source_of_truth='fordonskontrollen'));
end $$;
revoke all on function private.orderportal_maintenance(uuid) from public,anon;
grant execute on function private.orderportal_maintenance(uuid) to authenticated;
create function public.hub_orderportal_maintenance(p_tenant_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.orderportal_maintenance(p_tenant_id)$$;
revoke all on function public.hub_orderportal_maintenance(uuid) from public,anon;
grant execute on function public.hub_orderportal_maintenance(uuid) to authenticated;

select cron.schedule('humla-orderportal-maintenance','* * * * *','select private.orderportal_maintenance_tick();');
