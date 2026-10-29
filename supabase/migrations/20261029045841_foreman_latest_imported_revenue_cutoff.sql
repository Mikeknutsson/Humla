create function public.hub_foreman_revenue_cutoff_v1(p_tenant uuid,p_fiscal_year integer)returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cutoff date;uploaded timestamptz;
begin
 if auth.uid()is null or not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and(m.role in('owner','supervisor')or public.hub_has_permission(p_tenant,'kpi.read')))then raise exception 'Access denied'using errcode='42501';end if;
 if p_fiscal_year is null or p_fiscal_year<2001 or p_fiscal_year>2100 then raise exception 'Invalid fiscal year'using errcode='22023';end if;
 select max(r.occurred_on),max(b.created_at)into cutoff,uploaded
 from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 where r.tenant_id=p_tenant and r.data_kind='revenue' and b.data_kind='revenue' and r.is_valid and r.amount<>0
 and b.status in('completed','needs_review')and r.occurred_on between make_date(p_fiscal_year,9,1)and least(make_date(p_fiscal_year+1,8,31),(now()at time zone'Europe/Stockholm')::date);
 return jsonb_build_object('revenue_through',cutoff,'imported_at',uploaded,'basis','Senaste intäktsdatum bland giltiga importerade intäktsrader i verksamhetsåret. Stoppade och ogiltiga rader ingår inte.');
end $$;
revoke all on function public.hub_foreman_revenue_cutoff_v1(uuid,integer)from public,anon;
grant execute on function public.hub_foreman_revenue_cutoff_v1(uuid,integer)to authenticated;;
