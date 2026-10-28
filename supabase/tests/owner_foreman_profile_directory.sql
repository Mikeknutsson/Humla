-- Run with the real authenticated database role: a postgres-only query misses
-- the membership RLS regression that made the browser's directory empty.
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
set local role authenticated;
do $$
begin
 if (select count(*) from public.hub_foreman_profiles_v1('944597b6-9c46-4bef-998d-f19e23c4245b'))<>4 then raise exception 'Expected four foreman profiles';end if;
 if exists(select 1 from public.hub_tenant_members where role='supervisor' and tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b')then raise exception 'Membership RLS was broadened';end if;
 begin
  perform public.hub_foreman_profiles_v1('00000000-0000-0000-0000-000000000000');
  raise exception 'Cross-tenant directory allowed';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','7f87dae3-7055-473d-89e5-849905a65846',true);
set local role authenticated;
do $$begin
 begin
  perform public.hub_foreman_profiles_v1('944597b6-9c46-4bef-998d-f19e23c4245b');
  raise exception 'Non-owner directory allowed';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
