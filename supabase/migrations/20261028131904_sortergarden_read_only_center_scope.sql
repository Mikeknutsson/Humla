alter table private.hub_foreman_access_plans add column cost_centers text[];
CREATE OR REPLACE FUNCTION private.hub_transport_leader_facts_v2(p_tenant uuid, p_from date, p_to date, p_user uuid)
 RETURNS SETOF private.hub_kpi_prepared_display_facts
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare caller uuid:=auth.uid();owner_access boolean;generation uuid;authorized_centers text[];
begin
 if caller is null or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid scope or period' using errcode='22023';end if;
 select m.role='owner' into owner_access from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=caller and m.status='active';
 if owner_access is null or (p_user is not null and p_user<>caller and not owner_access) then raise exception 'Access denied' using errcode='42501';end if;
 if p_user is not null and not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=p_user and m.status='active') then raise exception 'Access denied' using errcode='42501';end if;
 select s.active_generation into generation from private.hub_kpi_report_state s where s.tenant_id=p_tenant;
 if generation is null then raise exception 'Published report unavailable';end if;
 select p.cost_centers into authorized_centers from private.hub_foreman_access_plans p where p.tenant_id=p_tenant and p.auth_user_id=coalesce(p_user,caller) and p.status='active';
 return query select f.* from private.hub_kpi_prepared_display_facts f
 where f.tenant_id=p_tenant and f.generation_id=generation and f.occurred_on between p_from and p_to
 and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
 and ((owner_access and p_user is null and f.cost_center='30') or (not(owner_access and p_user is null) and (case when authorized_centers is not null then f.cost_center=any(authorized_centers) else exists(
 select 1 from public.hub_transport_leader_units a where a.tenant_id=p_tenant and a.user_id=coalesce(p_user,caller)
 and a.unit_id=f.unit_id and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)) end)));
end $function$;

create function public.hub_sortergarden_bind_approved_account_v1(p_user uuid)returns jsonb language plpgsql security definer set search_path='' as $$
declare p record;n integer;
begin
 select * into p from private.hub_foreman_access_plans where tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b' and email='garden@elleholmsmaskin.se' for update;
 if not found or p.access_mode<>'read_only' or p.allow_login_delivery or p.cost_centers<>array['20'] or not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p.tenant_id and m.user_id=p.approved_by and m.status='active' and m.role='owner')then raise exception 'Approved KST 20 scope required';end if;
 if not exists(select 1 from auth.users u where u.id=p_user and lower(u.email)=p.email and u.raw_app_meta_data->>'humla_provisioning'='garden-approved-20261028')then raise exception 'Account identity mismatch';end if;
 if exists(select 1 from public.hub_tenant_members m where m.tenant_id=p.tenant_id and m.user_id=p_user and m.role<>'supervisor')then raise exception 'Existing privilege mismatch';end if;
 insert into public.hub_tenant_members(tenant_id,user_id,role,status,display_name)values(p.tenant_id,p_user,'supervisor','active',p.display_name)on conflict(tenant_id,user_id)do update set display_name=excluded.display_name,updated_at=now();
 insert into public.hub_transport_leader_units(tenant_id,user_id,unit_id,valid_from,assigned_by)
 select p.tenant_id,p_user,s.unit_id,coalesce(k.valid_from,'2025-09-01'::date),p.approved_by from private.hub_foreman_access_plan_units s join public.kpi_units k on k.id=s.unit_id and k.tenant_id=p.tenant_id where s.plan_id=p.id on conflict(tenant_id,user_id,unit_id,valid_from)do nothing;
 update private.hub_foreman_access_plans set auth_user_id=p_user,status='active',mapped_at=now()where id=p.id;
 select count(*)into n from private.hub_foreman_access_plan_units where plan_id=p.id;
 return jsonb_build_object('email',p.email,'role','supervisor','cost_centers',p.cost_centers,'mapped_units',n);
end $$;
revoke all on function public.hub_sortergarden_bind_approved_account_v1(uuid)from public,anon,authenticated;
grant execute on function public.hub_sortergarden_bind_approved_account_v1(uuid)to service_role;