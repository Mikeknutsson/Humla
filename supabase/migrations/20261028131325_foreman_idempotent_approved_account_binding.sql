alter table private.hub_foreman_access_plans add column auth_user_id uuid references auth.users(id),add column mapped_at timestamptz;
create function public.hub_foreman_bind_approved_accounts_v1(p_users jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare p record;u record;entry jsonb;uid uuid;n integer;answer jsonb:='[]';
begin
 if jsonb_typeof(p_users)<>'array' or jsonb_array_length(p_users)<>3 then raise exception 'Exactly three approved accounts required';end if;
 if (select count(distinct x->>'email')from jsonb_array_elements(p_users)x)<>3 then raise exception 'Duplicate account';end if;
 for p in select * from private.hub_foreman_access_plans where tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b' and email in('ola@elleholmsmaskin.se','pierre@elleholmsmaskin.se','marcus@elleholmsmaskin.se') order by email for update loop
  if p.access_mode<>'read_only' or p.allow_login_delivery or not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p.tenant_id and m.user_id=p.approved_by and m.role='owner' and m.status='active') then raise exception 'Approved scope required';end if;
  select x into entry from jsonb_array_elements(p_users)x where x->>'email'=p.email;
  uid:=(entry->>'id')::uuid;
  select * into u from auth.users where id=uid and lower(email)=p.email and raw_app_meta_data->>'humla_provisioning'='foreman-approved-20261028';
  if not found then raise exception 'Account identity mismatch';end if;
  if exists(select 1 from public.hub_tenant_members m where m.tenant_id=p.tenant_id and m.user_id=uid and m.role<>'supervisor')then raise exception 'Existing privilege mismatch';end if;
  select count(*) into n from private.hub_foreman_access_plan_units s join public.hub_objects o on o.id=s.unit_id and o.tenant_id=p.tenant_id and o.object_type='EconomicUnit' join public.kpi_units k on k.id=o.id and k.tenant_id=p.tenant_id where s.plan_id=p.id;
  if n=0 or n<>(select count(*)from private.hub_foreman_access_plan_units where plan_id=p.id)then raise exception 'Invalid canonical units';end if;
  insert into public.hub_tenant_members(tenant_id,user_id,role,status,display_name)values(p.tenant_id,uid,'supervisor','active',p.display_name)
  on conflict(tenant_id,user_id)do update set display_name=excluded.display_name,updated_at=now();
  insert into public.hub_transport_leader_units(tenant_id,user_id,unit_id,valid_from,assigned_by)
  select p.tenant_id,uid,s.unit_id,coalesce(k.valid_from,'2025-09-01'::date),p.approved_by from private.hub_foreman_access_plan_units s join public.kpi_units k on k.id=s.unit_id where s.plan_id=p.id
  on conflict(tenant_id,user_id,unit_id,valid_from)do nothing;
  if exists(select 1 from public.hub_transport_leader_units a where a.tenant_id=p.tenant_id and a.user_id=uid and not exists(select 1 from private.hub_foreman_access_plan_units s where s.plan_id=p.id and s.unit_id=a.unit_id))then raise exception 'Unexpected assignment';end if;
  update private.hub_foreman_access_plans set auth_user_id=uid,mapped_at=now(),status='active' where id=p.id;
  answer:=answer||jsonb_build_array(jsonb_build_object('email',p.email,'id',uid,'units',n,'role','supervisor'));
 end loop;
 if jsonb_array_length(answer)<>3 then raise exception 'Missing approved profile';end if;
 return answer;
end $$;
revoke all on function public.hub_foreman_bind_approved_accounts_v1(jsonb)from public,anon,authenticated;
grant execute on function public.hub_foreman_bind_approved_accounts_v1(jsonb)to service_role;
comment on function public.hub_foreman_bind_approved_accounts_v1(jsonb)is 'Idempotent service-only binding of exactly the three owner-approved foreman accounts. No email delivery and no general KPI permissions.';