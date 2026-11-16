create or replace function private.transport_validate_report_items(t uuid, items jsonb) returns jsonb
language plpgsql stable set search_path='' as $$
declare x jsonb; rule record; opt jsonb; qty numeric; site text; output jsonb='[]'; line jsonb; prices jsonb='[]'; amount numeric;
begin
 if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items)>30 then raise exception 'invalid_report_article';end if;
 for x in select value from jsonb_array_elements(items) loop
  select r.*,coalesce(a.data->>'display_name',a.data->>'name','Artikel') as label into rule
  from public.hub_transport_report_articles r join public.hub_objects a on a.id=r.article_id and a.tenant_id=t and a.status='active'
  where r.tenant_id=t and r.enabled and r.article_id::text=x->>'articleId';
  if not found or jsonb_typeof(x->'quantity') is distinct from 'number' then raise exception 'invalid_report_article';end if;
  if coalesce(jsonb_typeof(x->'comment'),'null') not in ('string','null')
   or length(x->>'comment')>500 then raise exception 'invalid_report_comment';end if;
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
   'siteId',opt->'siteId','siteLabel',site,'siteKind',rule.site_kind,'comment',nullif(trim(x->>'comment'),''));
  amount=(opt->>'price')::numeric;
  output=output||jsonb_build_array(line);
  prices=prices||jsonb_build_array(line||jsonb_build_object('unitPrice',amount,'amount',round(qty*amount,2)));
 end loop;
 return jsonb_build_object('items',output,'pricing',prices);
end $$;
revoke all on function private.transport_validate_report_items(uuid,jsonb) from public,anon,authenticated;
create or replace function private.transport_driver_command(p_tenant uuid,p_order uuid,p_version integer,p_request uuid,p_action text,p_data jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare person uuid;o public.hub_transport_orders;prev private.transport_driver_commands;v_payload jsonb;k text;v numeric;report jsonb;
begin
 person=private.transport_driver_person(p_tenant);
 if p_request is null or p_action not in ('start','pause','resume','report','complete','submit') or p_action is null or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>125000 then raise exception 'invalid_command';end if;
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
