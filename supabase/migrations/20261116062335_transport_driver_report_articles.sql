create table public.hub_transport_report_articles(
 tenant_id uuid not null references public.hub_tenants(id),
 article_id uuid not null references public.hub_objects(id),
 unit text not null check(unit in ('st','ton','tim','lass','kg','m³','km')),
 site_kind text not null check(site_kind in ('none','pickup','delivery')),
 enabled boolean not null,
 options jsonb not null check(jsonb_typeof(options)='array'),
 primary key(tenant_id,article_id)
);
alter table public.hub_transport_report_articles enable row level security;
revoke all on public.hub_transport_report_articles from public,anon,authenticated;
grant select on public.hub_transport_report_articles to authenticated;
create policy transport_article_management_read on public.hub_transport_report_articles for select to authenticated
 using(public.hub_has_permission(tenant_id,'transport.orders.manage'));

create function private.transport_report_article_save(t uuid,a uuid,u text,k text,e boolean, choices jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare x jsonb; n text; sid uuid; cost numeric; result jsonb='[]';
begin
 if auth.uid() is null or not public.hub_has_permission(t,'transport.orders.manage') then raise exception 'permission_denied'; end if;
 if not exists(select 1 from public.hub_objects where id=a and tenant_id=t and object_type='Article' and status='active') then raise exception 'invalid_article';end if;
 if u is null or u not in ('st','ton','tim','lass','kg','m³','km') or k is null or k not in ('none','pickup','delivery') or e is null
  or jsonb_typeof(choices) is distinct from 'array' or jsonb_array_length(choices)>50
  or (k='none' and jsonb_array_length(choices)<>1)
  or (e and jsonb_array_length(choices)=0) then raise exception 'invalid_article_options';end if;
 perform pg_advisory_xact_lock(hashtextextended(t::text||':orderportal-planning',0));
 for x in select value from jsonb_array_elements(choices) loop
  if jsonb_typeof(x) is distinct from 'object' or coalesce(jsonb_typeof(x->'price'),'null') not in ('number','null') then raise exception 'invalid_article_options';end if;
  cost=(x->>'price')::numeric;
  if cost is not null and (abs(cost)>1000000 or cost<>round(cost,4)) then raise exception 'invalid_article_options';end if;
  sid=null;
  if k<>'none' then
   n=trim(coalesce(x->>'name',''));
   if length(n) not between 1 and 120 then raise exception 'invalid_article_options';end if;
   select id into sid from public.hub_objects where tenant_id=t and object_type='TransportMaterialSite'
    and status='active' and lower(data->>'display_name')=lower(n) order by id limit 1;
   if sid is null then
    sid=gen_random_uuid();
    insert into public.hub_objects(id,tenant_id,object_type,source_of_truth,data)
     values(sid,t,'TransportMaterialSite','humla_transport',jsonb_build_object('display_name',n));
   end if;
   if exists(select 1 from jsonb_array_elements(result) r where r->>'siteId'=sid::text) then raise exception 'duplicate_site';end if;
  end if;
  result=result||jsonb_build_array(jsonb_build_object('siteId',sid,'price',cost));
 end loop;
 insert into public.hub_transport_report_articles(tenant_id,article_id,unit,site_kind,enabled,options)
 values(t,a,u,k,e,result) on conflict(tenant_id,article_id)
 do update set unit=excluded.unit,site_kind=excluded.site_kind,enabled=excluded.enabled,options=excluded.options;
end $$;
revoke all on function private.transport_report_article_save(uuid,uuid,text,text,boolean,jsonb) from public,anon;
grant execute on function private.transport_report_article_save(uuid,uuid,text,text,boolean,jsonb) to authenticated;
create function public.hub_transport_report_article_save(t uuid,a uuid,u text,k text,e boolean,choices jsonb)
 returns void language sql security invoker set search_path='' as $$select private.transport_report_article_save(t,a,u,k,e,choices)$$;
revoke all on function public.hub_transport_report_article_save(uuid,uuid,text,text,boolean,jsonb) from public,anon;
grant execute on function public.hub_transport_report_article_save(uuid,uuid,text,text,boolean,jsonb) to authenticated;

create function private.transport_report_catalog(t uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform private.transport_driver_person(t);
 return coalesce((select jsonb_agg(jsonb_build_object('id',r.article_id,'label',coalesce(a.data->>'display_name',a.data->>'name'),'unit',r.unit,'siteKind',r.site_kind,
  'sites',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'label',s.data->>'display_name') order by s.data->>'display_name'),'[]')
   from jsonb_array_elements(r.options) opt join public.hub_objects s on s.id::text=opt->>'siteId' and s.tenant_id=t and s.status='active'))
  order by a.data->>'display_name')
 from public.hub_transport_report_articles r join public.hub_objects a on a.id=r.article_id and a.tenant_id=t and a.status='active'
 where r.tenant_id=t and r.enabled),'[]');
end $$;
revoke all on function private.transport_report_catalog(uuid) from public,anon;
grant execute on function private.transport_report_catalog(uuid) to authenticated;
create function public.hub_transport_report_catalog(t uuid) returns jsonb
 language sql stable security invoker set search_path='' as $$select private.transport_report_catalog(t)$$;
revoke all on function public.hub_transport_report_catalog(uuid) from public,anon;
grant execute on function public.hub_transport_report_catalog(uuid) to authenticated;

create function private.transport_validate_report_items(t uuid, items jsonb) returns jsonb
language plpgsql stable set search_path='' as $$
declare x jsonb; rule record; opt jsonb; qty numeric; site text; output jsonb='[]'; line jsonb; prices jsonb='[]'; amount numeric;
begin
 if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items)>30 then raise exception 'invalid_report_article';end if;
 for x in select value from jsonb_array_elements(items) loop
  select r.*,coalesce(a.data->>'display_name',a.data->>'name','Artikel') as label into rule
  from public.hub_transport_report_articles r join public.hub_objects a on a.id=r.article_id and a.tenant_id=t and a.status='active'
  where r.tenant_id=t and r.enabled and r.article_id::text=x->>'articleId';
  if not found or jsonb_typeof(x->'quantity') is distinct from 'number' then raise exception 'invalid_report_article';end if;
  qty=(x->>'quantity')::numeric;
  if qty<=0 or qty>100000 or qty<>round(qty,4) or (rule.unit in ('st','lass') and qty<>trunc(qty)) then raise exception 'invalid_report_article';end if;
  if rule.site_kind='none' and nullif(x->>'siteId','') is not null then raise exception 'invalid_report_site';end if;
  select value into opt from jsonb_array_elements(rule.options) where value->>'siteId' is not distinct from nullif(x->>'siteId','');
  if not found then raise exception 'invalid_report_site';end if;
  site=null;
  if rule.site_kind<>'none' then
   select data->>'display_name' into site from public.hub_objects where tenant_id=t and id::text=opt->>'siteId'
    and status='active' and object_type='TransportMaterialSite';
   if site is null then raise exception 'invalid_report_site';end if;
  end if;
  if exists(select 1 from jsonb_array_elements(output) old where old->>'articleId'=rule.article_id::text
   and old->>'siteId' is not distinct from opt->>'siteId') then raise exception 'duplicate_report_article';end if;
  line=jsonb_build_object('articleId',rule.article_id,'label',rule.label,'unit',rule.unit,'quantity',qty,
   'siteId',opt->'siteId','siteLabel',site,'siteKind',rule.site_kind);
  amount=(opt->>'price')::numeric;
  output=output||jsonb_build_array(line);
  prices=prices||jsonb_build_array(line||jsonb_build_object('unitPrice',amount,'amount',round(qty*amount,2)));
 end loop;
 return jsonb_build_object('items',output,'pricing',prices);
end $$;
revoke all on function private.transport_validate_report_items(uuid,jsonb) from public,anon,authenticated;
-- Final handover is atomic, audited and permanently locked for the driver.
create or replace function private.transport_driver_orders(p_tenant uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p uuid;
begin
 p=private.transport_driver_person(p_tenant);
 return coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'number',o.order_number,'version',o.version,
 'title',o.payload->>'title','status',o.payload->>'status','execution',o.payload->>'execution_state',
 'start',o.payload->>'start','end',o.payload->>'end','customer',o.payload->>'customer','project',o.payload->>'project',
 'location',o.payload->>'location','instruction',o.payload->>'instruction','vehicle',o.payload->>'vehicle',
 'contactName',o.payload->>'contactName','contactPhone',o.payload->>'contactPhone','report',(o.payload->'driverReport')-'pricing','submittedAt',o.payload->>'driverSubmittedAt',
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
 report=coalesce(o.payload->'driverReport','{}')-array['savedAt','savedBy'];
 if p_data?'items' then
  report=report||private.transport_validate_report_items(p_tenant,p_data->'items');
 end if;
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
