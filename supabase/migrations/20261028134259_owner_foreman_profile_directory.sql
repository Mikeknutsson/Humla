create function public.hub_foreman_profiles_v1(p_tenant uuid)
returns table(user_id uuid,display_name text,role text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.hub_tenant_members owner_member where owner_member.tenant_id=p_tenant and owner_member.user_id=auth.uid() and owner_member.role='owner' and owner_member.status='active')then
 raise exception 'Owner access required' using errcode='42501';end if;
 return query select m.user_id,m.display_name,m.role from public.hub_tenant_members m where m.tenant_id=p_tenant and m.status='active' and m.role='supervisor' order by m.display_name,m.user_id;
end $$;
revoke all on function public.hub_foreman_profiles_v1(uuid)from public,anon;
grant execute on function public.hub_foreman_profiles_v1(uuid)to authenticated;
comment on function public.hub_foreman_profiles_v1(uuid)is 'Owner-only supervisor directory for profile previews and assignments. Does not broaden member-table RLS or grant access to other tenants.';
