create function private.hub_workify_saw_control(p_tenant uuid,p_from date,p_to date,p_months integer[])
returns table (article text, workify_status text, amount numeric)
language sql stable security definer set search_path = ''
as $$
  select f.original->>'Artikelnummer', coalesce(f.original->>'Orderstatus',''), sum(f.amount)
  from private.hub_kpi_prepared_facts f
  join private.hub_kpi_report_state s on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
  where f.tenant_id=p_tenant and f.source='Workify' and f.kind='revenue'
    and f.original->>'Artikelnummer' in ('12-04','12-041')
    and f.occurred_on between p_from and p_to and p_to-p_from between 0 and 366
    and (p_months is null or extract(month from f.occurred_on)::integer=any(p_months))
    and exists (select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant
      and m.user_id=(select auth.uid()) and m.role='owner' and m.status='active')
  group by 1,2;
$$;
revoke all on function private.hub_workify_saw_control(uuid,date,date,integer[]) from public,anon;
grant execute on function private.hub_workify_saw_control(uuid,date,date,integer[]) to authenticated;

create function public.hub_workify_saw_control(p_tenant uuid,p_from date,p_to date,p_months integer[])
returns table (article text, workify_status text, amount numeric)
language sql stable security invoker set search_path = ''
as $$ select * from private.hub_workify_saw_control(p_tenant,p_from,p_to,p_months) $$;
revoke all on function public.hub_workify_saw_control(uuid,date,date,integer[]) from public,anon;
grant execute on function public.hub_workify_saw_control(uuid,date,date,integer[]) to authenticated;
