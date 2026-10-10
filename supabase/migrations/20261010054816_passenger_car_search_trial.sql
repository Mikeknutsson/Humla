-- Separate bounded passenger-car pilot; original truck trial remains intact.
create table private.hub_car_search_trials (
 tenant_id uuid not null references public.hub_tenants(id),
 asset_id uuid not null references public.hub_objects(id),
 actor_id uuid not null, claim uuid not null default gen_random_uuid(),
 started_at timestamptz not null default now(), finished_at timestamptz,
 result jsonb check(result is null or octet_length(result::text)<=40000),
 primary key(tenant_id,asset_id)
);
alter table private.hub_car_search_trials enable row level security;
revoke all on private.hub_car_search_trials from public,anon,authenticated;
create function private.hub_car_search_trial_v1(p_tenant_id uuid,p_asset uuid,p_action text,p_claim uuid default null,p_result jsonb default null)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='5s' as $$
declare r private.hub_car_search_trials;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'fleet.read') or not public.hub_has_permission(p_tenant_id,'fleet.manage') then raise exception 'Fordonsadministratör krävs' using errcode='42501';end if;
 if p_tenant_id<>'944597b6-9c46-4bef-998d-f19e23c4245b'::uuid or not exists(select 1 from public.hub_objects o where o.id=p_asset and o.tenant_id=p_tenant_id and o.object_type='Vehicle' and o.data->>'vehicle_type'='Personbil' and public.hub_resolve_canonical_object_v1(p_tenant_id,o.id)=o.id) then raise exception 'Personbil med verifierat Humla-ID krävs' using errcode='42501';end if;
 if p_action='reserve' then
  -- Serialize the tenant-wide count and insert, including different cars/users.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('car-search-pilot:'||p_tenant_id::text,0));
  select * into r from private.hub_car_search_trials where tenant_id=p_tenant_id and asset_id=p_asset;
  if found then return jsonb_build_object('reserved',false,'result',r.result,'started_at',r.started_at);end if;
  if (select count(*) from private.hub_car_search_trials where tenant_id=p_tenant_id)>=3 then return jsonb_build_object('reserved',false,'limit_reached',true);end if;
  insert into private.hub_car_search_trials(tenant_id,asset_id,actor_id) values(p_tenant_id,p_asset,auth.uid()) returning * into r;
  return jsonb_build_object('reserved',true,'claim',r.claim,'started_at',r.started_at);
 elsif p_action='finish' then
  if p_result is null or jsonb_typeof(p_result)<>'object' or octet_length(p_result::text)>40000 then raise exception 'Ogiltigt testresultat';end if;
  update private.hub_car_search_trials set result=p_result,finished_at=now() where tenant_id=p_tenant_id and asset_id=p_asset and actor_id=auth.uid() and claim=p_claim and result is null;
  if not found then raise exception 'Testreservation saknas';end if;
  return jsonb_build_object('saved',true);
 elsif p_action='read' then
  select * into r from private.hub_car_search_trials where tenant_id=p_tenant_id and asset_id=p_asset;
  return jsonb_build_object('result',r.result,'started_at',r.started_at);
 end if;
 raise exception 'Ogiltig åtgärd';
end $$;
revoke all on function private.hub_car_search_trial_v1(uuid,uuid,text,uuid,jsonb) from public,anon;
grant execute on function private.hub_car_search_trial_v1(uuid,uuid,text,uuid,jsonb) to authenticated;
create function public.hub_car_search_trial_v1(p_tenant_id uuid,p_asset uuid,p_action text,p_claim uuid default null,p_result jsonb default null)
returns jsonb language sql security invoker set search_path='' as $$ select private.hub_car_search_trial_v1(p_tenant_id,p_asset,p_action,p_claim,p_result) $$;
revoke all on function public.hub_car_search_trial_v1(uuid,uuid,text,uuid,jsonb) from public,anon;
grant execute on function public.hub_car_search_trial_v1(uuid,uuid,text,uuid,jsonb) to authenticated;
