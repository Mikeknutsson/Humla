alter table public.hub_orderportal_prices add column retired_at timestamptz, add column retired_by uuid;
create function private.orderportal_retire_price(p_tenant_id uuid,p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'permission_denied';end if;
 update public.hub_orderportal_prices set retired_at=now(),retired_by=auth.uid() where id=p_id and tenant_id=p_tenant_id and retired_at is null;
 if not found then raise exception 'price_not_found';end if;
end $$;
revoke all on function private.orderportal_retire_price(uuid,uuid) from public,anon;
grant execute on function private.orderportal_retire_price(uuid,uuid) to authenticated;
create function public.hub_orderportal_retire_price(p_tenant_id uuid,p_id uuid) returns void language sql security invoker set search_path='' as $$select private.orderportal_retire_price(p_tenant_id,p_id)$$;
revoke all on function public.hub_orderportal_retire_price(uuid,uuid) from public,anon;
grant execute on function public.hub_orderportal_retire_price(uuid,uuid) to authenticated;
-- Preserve the reviewed function bodies and add retirement guards.
do $patch$
declare d text;
begin
 d=pg_get_functiondef('public.hub_orderportal_quote(uuid,uuid,uuid,uuid,date,text,uuid,uuid)'::regprocedure);
 d=replace(d,'where p.tenant_id=p_tenant_id and p.article_id=p_article','where p.retired_at is null and p.tenant_id=p_tenant_id and p.article_id=p_article');execute d;
 d=pg_get_functiondef('private.orderportal_catalog_add(uuid,text,jsonb)'::regprocedure);
 d=replace(d,'from public.hub_orderportal_prices where tenant_id=p_tenant_id','from public.hub_orderportal_prices where retired_at is null and tenant_id=p_tenant_id');execute d;
 d=pg_get_functiondef('private.orderportal_save_priced(uuid,uuid,integer,uuid,jsonb)'::regprocedure);
 d=replace(d, 'select * into v_list from public.hub_orderportal_price_lists', $guard$
 if v_price.retired_at is not null and not exists(select 1 from public.hub_orderportal_orders o cross join lateral jsonb_array_elements(o.payload->'lines') old_line where o.id=p_id and o.tenant_id=p_tenant_id and old_line->>'id'=v_line->>'id' and old_line->>'priceRuleId'=v_price.id::text) then raise exception 'price_context_changed';end if;
 select * into v_list from public.hub_orderportal_price_lists$guard$);execute d;
end $patch$;
