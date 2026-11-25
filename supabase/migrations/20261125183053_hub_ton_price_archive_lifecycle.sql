alter table public.hub_ton_price_offers
  add column status text not null default 'created' check (status in ('created','sent','accepted')),
  add column deleted_at timestamptz,
  add column trash_fingerprint text;


create function private.hub_ton_price_archive_change(p_tenant uuid,p_id uuid,p_action text)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare offer public.hub_ton_price_offers%rowtype;
begin
  if not public.hub_can_use_ton_price(p_tenant) then return false; end if;
  select * into offer from public.hub_ton_price_offers
  where tenant_id=p_tenant and id=p_id
    and (created_by=(select auth.uid()) or public.hub_has_permission(p_tenant,'kpi.manage'))
  for update;
  if not found then return false; end if;
  if p_action='trash' and offer.deleted_at is null then
    update public.hub_ton_price_offers set deleted_at=now(),trash_fingerprint=fingerprint,
      fingerprint=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','')
      where tenant_id=p_tenant and id=p_id;
  elsif p_action='restore' and offer.deleted_at is not null then
    update public.hub_ton_price_offers set deleted_at=null,
      fingerprint=trash_fingerprint,trash_fingerprint=null where tenant_id=p_tenant and id=p_id;
  elsif p_action in ('created','sent','accepted') and offer.deleted_at is null then
    update public.hub_ton_price_offers set status=p_action where tenant_id=p_tenant and id=p_id;
  elsif p_action not in ('trash','restore') then
    return false;
  end if;
  return true;
end;
$$;
revoke all on function private.hub_ton_price_archive_change(uuid,uuid,text) from public,anon;
grant execute on function private.hub_ton_price_archive_change(uuid,uuid,text) to authenticated;

create function public.hub_ton_price_archive_change(p_tenant uuid,p_id uuid,p_action text)
returns boolean language sql security invoker set search_path = ''
as $$ select private.hub_ton_price_archive_change(p_tenant,p_id,p_action) $$;
revoke all on function public.hub_ton_price_archive_change(uuid,uuid,text) from public,anon;
grant execute on function public.hub_ton_price_archive_change(uuid,uuid,text) to authenticated;

create function public.hub_ton_price_archive_groups(p_tenant uuid,p_search text,p_trash boolean,p_offset integer)
returns table (group_id uuid, entries jsonb)
language sql stable security invoker set search_path = ''
as $$
  with recursive archive as materialized (
    select id,source_offer_id,created_at,offer_date,customer,project,destinations,materials,status,deleted_at
    from public.hub_ton_price_offers where tenant_id=p_tenant and public.hub_can_use_ton_price(p_tenant)
  ), lineage as (
    select a.*, a.id as root_id, 0 as depth from archive a
    where not exists (select 1 from archive parent where parent.id=a.source_offer_id)
    union all
    select a.*,parent.root_id,parent.depth+1 from archive a join lineage parent on a.source_offer_id=parent.id
  ), visible as (
    select * from lineage where (deleted_at is not null)=p_trash
  ), chosen as (
    select root_id,max(case when p_trash then deleted_at else created_at end) as newest
    from visible
    group by root_id
    having bool_or(strpos(lower(concat_ws(' ',customer,project,array_to_string(destinations,' '))),lower(left(coalesce(p_search,''),120)))>0)
    order by newest desc,root_id desc
    offset greatest(p_offset,0) limit 26
  )
  select c.root_id, jsonb_agg(to_jsonb(v)-'created_at'-'root_id' order by v.depth,v.created_at,v.id)
  from chosen c join visible v on v.root_id=c.root_id
  group by c.root_id,c.newest
  order by c.newest desc,c.root_id desc;
$$;
revoke all on function public.hub_ton_price_archive_groups(uuid,text,boolean,integer) from public,anon;
grant execute on function public.hub_ton_price_archive_groups(uuid,text,boolean,integer) to authenticated;
