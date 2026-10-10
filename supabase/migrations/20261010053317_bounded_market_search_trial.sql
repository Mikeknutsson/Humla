-- One explicitly approved search trial, not a recurring collection service.
-- Atomic tenant PK prevents duplicate spend across tabs, users and retries.
create table private.hub_market_search_trial (
 tenant_id uuid primary key references public.hub_tenants(id),
 asset_id uuid not null references public.hub_objects(id),
 actor_id uuid not null, claim uuid not null default gen_random_uuid(),
 started_at timestamptz not null default now(), finished_at timestamptz,
 result jsonb check(result is null or octet_length(result::text)<=40000)
);
alter table private.hub_market_search_trial enable row level security;
revoke all on private.hub_market_search_trial from public,anon,authenticated;
create function private.hub_market_search_trial_v1(p_tenant_id uuid,p_asset uuid,p_action text,p_claim uuid default null,p_result jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.hub_market_search_trial; inserted boolean:=false;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'fleet.read') or not public.hub_has_permission(p_tenant_id,'fleet.manage') then raise exception 'Fordonsadministratör krävs' using errcode='42501';end if;
 -- Approval covers this asset and workspace only. Expanding the trial requires a new decision.
 if p_tenant_id<>'944597b6-9c46-4bef-998d-f19e23c4245b'::uuid or p_asset<>'741e093a-93ba-4266-abf8-2288789d1c84'::uuid or not exists(select 1 from public.hub_objects where id=p_asset and tenant_id=p_tenant_id and object_type='Vehicle') then raise exception 'Testet omfattar inte detta fordon' using errcode='42501';end if;
 if p_action='reserve' then
  insert into private.hub_market_search_trial(tenant_id,asset_id,actor_id) values(p_tenant_id,p_asset,auth.uid()) on conflict do nothing returning * into r;
  inserted:=found;
  if not inserted then select * into r from private.hub_market_search_trial where tenant_id=p_tenant_id;end if;
  return jsonb_build_object('reserved',inserted,'claim',case when inserted then r.claim else null end,'result',r.result,'started_at',r.started_at);
 elsif p_action='finish' then
  if p_result is null or jsonb_typeof(p_result)<>'object' or octet_length(p_result::text)>40000 then raise exception 'Ogiltigt testresultat';end if;
  update private.hub_market_search_trial set result=p_result,finished_at=now() where tenant_id=p_tenant_id and asset_id=p_asset and actor_id=auth.uid() and claim=p_claim and result is null;
  if not found then raise exception 'Testreservation saknas';end if;
  return jsonb_build_object('saved',true);
 elsif p_action='read' then
  select * into r from private.hub_market_search_trial where tenant_id=p_tenant_id;
  return jsonb_build_object('result',r.result,'started_at',r.started_at);
 end if;
 raise exception 'Ogiltig åtgärd';
end $$;
revoke all on function private.hub_market_search_trial_v1(uuid,uuid,text,uuid,jsonb) from public,anon;
grant execute on function private.hub_market_search_trial_v1(uuid,uuid,text,uuid,jsonb) to authenticated;
create function public.hub_market_search_trial_v1(p_tenant_id uuid,p_asset uuid,p_action text,p_claim uuid default null,p_result jsonb default null)
returns jsonb language sql security invoker set search_path='' as $$ select private.hub_market_search_trial_v1(p_tenant_id,p_asset,p_action,p_claim,p_result) $$;
revoke all on function public.hub_market_search_trial_v1(uuid,uuid,text,uuid,jsonb) from public,anon;
grant execute on function public.hub_market_search_trial_v1(uuid,uuid,text,uuid,jsonb) to authenticated;
