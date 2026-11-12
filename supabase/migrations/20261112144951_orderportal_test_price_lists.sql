-- Separate test catalog. No KPI sources or financial purchase-price tables are changed.
create table public.hub_orderportal_price_lists (
 id uuid primary key references public.hub_objects(id), tenant_id uuid not null references public.hub_tenants(id),
 name text not null check(length(trim(name)) between 1 and 120), scope text not null check(scope in ('base','customer','project')),
 target_id uuid references public.hub_objects(id), created_by uuid not null, created_at timestamptz not null default now(),
 is_test boolean not null default true check(is_test), check((scope='base')=(target_id is null))
);
create unique index orderportal_one_base_price_list on public.hub_orderportal_price_lists(tenant_id) where scope='base';
create unique index orderportal_price_list_name on public.hub_orderportal_price_lists(tenant_id,lower(name));
create table public.hub_orderportal_prices (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.hub_tenants(id),
 list_id uuid not null references public.hub_orderportal_price_lists(id), article_id uuid not null references public.hub_objects(id),
 pickup_id uuid references public.hub_objects(id), delivery_id uuid references public.hub_objects(id),
 unit text not null check(length(trim(unit)) between 1 and 20), sale_price numeric(16,4) not null check(sale_price>=0 and sale_price<>'NaN'::numeric),
 purchase_price numeric(16,4) check(purchase_price>=0 and purchase_price<>'NaN'::numeric), valid_from date not null, valid_to date,
 created_by uuid not null, created_at timestamptz not null default now(), check(valid_to is null or valid_to>=valid_from)
);
create index orderportal_prices_lookup on public.hub_orderportal_prices(tenant_id,article_id,list_id);
alter table public.hub_orderportal_price_lists enable row level security;
alter table public.hub_orderportal_prices enable row level security;
revoke all on public.hub_orderportal_price_lists,public.hub_orderportal_prices from anon,authenticated;
grant select on public.hub_orderportal_price_lists,public.hub_orderportal_prices to authenticated;
create policy orderportal_price_lists_read on public.hub_orderportal_price_lists for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.manage'));
create policy orderportal_prices_read on public.hub_orderportal_prices for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.manage'));

-- Append-only price records: dated prices and original order snapshots stay traceable.
create function private.orderportal_catalog_add(p_tenant_id uuid,p_kind text,p_data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid=gen_random_uuid(); v_ref uuid; v_key text; v_expected text; v_scope text; v_from date; v_to date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'permission_denied';end if;
 if octet_length(p_data::text)>20000 then raise exception 'invalid_payload';end if;
 if p_kind in ('list','site') then
 if length(trim(coalesce(p_data->>'name',''))) not between 1 and 120 then raise exception 'name_required';end if;
 if p_kind='list' then
 v_scope=p_data->>'scope';v_ref=nullif(p_data->>'targetId','')::uuid;
 if v_scope not in ('base','customer','project') or v_scope is null or (v_scope='base')<>(v_ref is null) then raise exception 'invalid_scope';end if;
 if v_ref is not null and not exists(select 1 from public.hub_objects where id=v_ref and tenant_id=p_tenant_id and status='active' and object_type=case v_scope when 'customer' then 'Customer' else 'Project' end) then raise exception 'invalid_target';end if;
 insert into public.hub_objects(id,tenant_id,object_type,data,source_of_truth) values(v_id,p_tenant_id,'TestPriceList',jsonb_build_object('display_name',trim(p_data->>'name'),'is_test',true),'humla_orderportal_test');
 insert into public.hub_orderportal_price_lists(id,tenant_id,name,scope,target_id,created_by) values(v_id,p_tenant_id,trim(p_data->>'name'),v_scope,v_ref,auth.uid());
 else
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||'orderportal-site',0));
 if exists(select 1 from public.hub_objects where tenant_id=p_tenant_id and object_type='TestMaterialSite' and lower(trim(data->>'display_name'))=lower(trim(p_data->>'name'))) then raise exception 'site_already_exists';end if;
 insert into public.hub_objects(id,tenant_id,object_type,data,source_of_truth) values(v_id,p_tenant_id,'TestMaterialSite',jsonb_build_object('display_name',trim(p_data->>'name'),'is_test',true,'created_by',auth.uid()),'humla_orderportal_test');
 end if;
 elsif p_kind='price' then
 if not exists(select 1 from public.hub_orderportal_price_lists where id=(p_data->>'listId')::uuid and tenant_id=p_tenant_id) then raise exception 'invalid_list';end if;
 foreach v_key in array array['articleId','pickupId','deliveryId'] loop
 v_ref=nullif(p_data->>v_key,'')::uuid;v_expected=case v_key when 'articleId' then 'Article' else 'TestMaterialSite' end;
 if (v_key='articleId' and v_ref is null) or (v_ref is not null and not exists(select 1 from public.hub_objects where id=v_ref and tenant_id=p_tenant_id and status='active' and object_type=v_expected)) then raise exception 'invalid_reference';end if;
 end loop;
 v_from=(p_data->>'validFrom')::date;v_to=nullif(p_data->>'validTo','')::date;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||(p_data->>'listId'),0));
 if exists(select 1 from public.hub_orderportal_prices where tenant_id=p_tenant_id and list_id=(p_data->>'listId')::uuid and article_id=(p_data->>'articleId')::uuid and pickup_id is not distinct from nullif(p_data->>'pickupId','')::uuid and delivery_id is not distinct from nullif(p_data->>'deliveryId','')::uuid and unit=trim(p_data->>'unit') and daterange(valid_from,valid_to,'[]') && daterange(v_from,v_to,'[]')) then raise exception 'overlapping_price_period';end if;
 insert into public.hub_orderportal_prices(id,tenant_id,list_id,article_id,pickup_id,delivery_id,unit,sale_price,purchase_price,valid_from,valid_to,created_by)
 values(v_id,p_tenant_id,(p_data->>'listId')::uuid,(p_data->>'articleId')::uuid,nullif(p_data->>'pickupId','')::uuid,nullif(p_data->>'deliveryId','')::uuid,trim(p_data->>'unit'),(p_data->>'salePrice')::numeric,nullif(p_data->>'purchasePrice','')::numeric,v_from,v_to,auth.uid());
 else raise exception 'invalid_kind';end if;
 return v_id;
end $$;
revoke all on function private.orderportal_catalog_add(uuid,text,jsonb) from public,anon;
grant execute on function private.orderportal_catalog_add(uuid,text,jsonb) to authenticated;
create function public.hub_orderportal_catalog_add(p_tenant_id uuid,p_kind text,p_data jsonb) returns uuid language sql security invoker set search_path='' as $$select private.orderportal_catalog_add(p_tenant_id,p_kind,p_data)$$;
revoke all on function public.hub_orderportal_catalog_add(uuid,text,jsonb) from public,anon;
grant execute on function public.hub_orderportal_catalog_add(uuid,text,jsonb) to authenticated;

-- Quote selection is in Hub: project > customer > base, then most specific location.
create function public.hub_orderportal_quote(p_tenant_id uuid,p_article uuid,p_customer uuid,p_project uuid,p_day date,p_unit text,p_pickup uuid default null,p_delivery uuid default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_candidates jsonb; v_best integer; v_count integer; v_result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'permission_denied';end if;
 select jsonb_agg(to_jsonb(p)||jsonb_build_object('list_name',l.name,'scope',l.scope,'rank',(case l.scope when 'project' then 30 when 'customer' then 20 else 10 end)+(case when p.pickup_id is null then 0 else 1 end)+(case when p.delivery_id is null then 0 else 1 end))) into v_candidates
 from public.hub_orderportal_prices p join public.hub_orderportal_price_lists l on l.id=p.list_id and l.tenant_id=p.tenant_id
 where p.tenant_id=p_tenant_id and p.article_id=p_article and p.unit=p_unit and p_day>=p.valid_from and (p.valid_to is null or p_day<=p.valid_to)
 and (l.scope='base' or (l.scope='customer' and l.target_id=p_customer) or (l.scope='project' and l.target_id=p_project));
 if exists(select 1 from jsonb_array_elements(coalesce(v_candidates,'[]')) x where ((p_pickup is null and x->>'pickup_id' is not null) or (p_delivery is null and x->>'delivery_id' is not null)) and (p_pickup is null or x->>'pickup_id' is null or x->>'pickup_id'=p_pickup::text) and (p_delivery is null or x->>'delivery_id' is null or x->>'delivery_id'=p_delivery::text)) then return jsonb_build_object('status','site_required');end if;
 select jsonb_agg(x) into v_candidates from jsonb_array_elements(coalesce(v_candidates,'[]')) x where (x->>'pickup_id' is null or x->>'pickup_id'=p_pickup::text) and (x->>'delivery_id' is null or x->>'delivery_id'=p_delivery::text);
 select max((x->>'rank')::integer) into v_best from jsonb_array_elements(coalesce(v_candidates,'[]')) x;
 if v_best is null then return jsonb_build_object('status','missing');end if;
 select count(*),jsonb_agg(x)->0 into v_count,v_result from jsonb_array_elements(v_candidates) x where (x->>'rank')::integer=v_best;
 if v_count<>1 then return jsonb_build_object('status','ambiguous');end if;
 return jsonb_build_object('status','matched','price',v_result);
end $$;
revoke all on function public.hub_orderportal_quote(uuid,uuid,uuid,uuid,date,text,uuid,uuid) from public,anon;
grant execute on function public.hub_orderportal_quote(uuid,uuid,uuid,uuid,date,text,uuid,uuid) to authenticated;

create function private.orderportal_save_priced(p_tenant_id uuid,p_id uuid,p_expected_version integer,p_request_id uuid,p_payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_line jsonb;v_lines jsonb='[]';v_price public.hub_orderportal_prices;v_list public.hub_orderportal_price_lists;v_ref uuid;v_key text;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'permission_denied';end if;
 if octet_length(p_payload::text)>250000 or jsonb_typeof(p_payload->'lines') is distinct from 'array' or jsonb_array_length(p_payload->'lines')>200 then raise exception 'invalid_lines';end if;
 for v_line in select value from jsonb_array_elements(p_payload->'lines') loop
 foreach v_key in array array['articleId','pickupSiteId','deliverySiteId'] loop
 v_ref=nullif(v_line->>v_key,'')::uuid;
 if v_ref is not null and not exists(select 1 from public.hub_objects where id=v_ref and tenant_id=p_tenant_id and status='active' and object_type=case v_key when 'articleId' then 'Article' else 'TestMaterialSite' end) then raise exception 'invalid_line_reference';end if;
 end loop;
 if nullif(v_line->>'purchasePrice','') is not null and ((v_line->>'purchasePrice')::numeric<0 or (v_line->>'purchasePrice')::numeric='NaN'::numeric) then raise exception 'invalid_purchase_price';end if;
 if nullif(v_line->>'priceRuleId','') is not null then
 select * into v_price from public.hub_orderportal_prices where id=(v_line->>'priceRuleId')::uuid and tenant_id=p_tenant_id;
 if not found then raise exception 'price_not_found';end if;
 select * into v_list from public.hub_orderportal_price_lists where id=v_price.list_id and tenant_id=p_tenant_id;
 if v_price.article_id is distinct from nullif(v_line->>'articleId','')::uuid or v_price.unit is distinct from v_line->>'unit' or (v_line->>'date')::date<v_price.valid_from or (v_price.valid_to is not null and (v_line->>'date')::date>v_price.valid_to) or (v_price.pickup_id is not null and v_price.pickup_id is distinct from nullif(v_line->>'pickupSiteId','')::uuid) or (v_price.delivery_id is not null and v_price.delivery_id is distinct from nullif(v_line->>'deliverySiteId','')::uuid) or (v_list.scope='customer' and v_list.target_id is distinct from nullif(p_payload->>'customerId','')::uuid) or (v_list.scope='project' and v_list.target_id is distinct from nullif(p_payload->>'projectId','')::uuid) or v_price.sale_price is distinct from (v_line->>'price')::numeric then raise exception 'price_context_changed';end if;
 v_line=v_line||jsonb_build_object('priceSource',v_list.name,'priceSnapshot',jsonb_build_object('ruleId',v_price.id,'listId',v_list.id,'listName',v_list.name,'scope',v_list.scope,'salePrice',v_price.sale_price,'purchasePrice',v_price.purchase_price,'unit',v_price.unit,'validFrom',v_price.valid_from,'validTo',v_price.valid_to,'pickupId',v_price.pickup_id,'deliveryId',v_price.delivery_id));
 if v_price.purchase_price is not null then v_line=v_line||jsonb_build_object('purchasePrice',v_price.purchase_price);end if;
 else v_line=(v_line-'priceSnapshot')||jsonb_build_object('priceSource','Manuellt testpris');end if;
 v_lines=v_lines||jsonb_build_array(v_line);
 end loop;
 return private.orderportal_save(p_tenant_id,p_id,p_expected_version,p_request_id,jsonb_set(p_payload,'{lines}',v_lines));
end $$;
revoke all on function private.orderportal_save_priced(uuid,uuid,integer,uuid,jsonb) from public,anon;
grant execute on function private.orderportal_save_priced(uuid,uuid,integer,uuid,jsonb) to authenticated;
create or replace function public.hub_orderportal_save(p_tenant_id uuid,p_id uuid,p_expected_version integer,p_request_id uuid,p_payload jsonb)
returns uuid language sql security invoker set search_path='' as $$select private.orderportal_save_priced(p_tenant_id,p_id,p_expected_version,p_request_id,p_payload)$$;
