create function public.hub_ton_price_workify_customers(p_tenant_id uuid)
returns table (name text)
language sql stable security invoker set search_path = ''
as $$
  select min(customer.name) as name
  from public.kpi_import_rows r
  join public.kpi_import_batches b on b.id = r.batch_id and b.tenant_id = r.tenant_id
  cross join lateral (select btrim(r.source_data->>'Kundnamn') as name) customer
  where r.tenant_id = p_tenant_id
    and (select public.hub_has_permission(p_tenant_id, 'kpi.manage'))
    and r.data_kind = 'revenue' and r.is_valid
    and b.status in ('completed', 'needs_review')
    and (r.source_system = 'workify_file' or
      (r.source_system is null and r.source_data ?& array['Ordernummer','Artikelnummer','Artikeldatum']))
    and length(customer.name) between 1 and 240
  group by lower(customer.name)
  order by lower(customer.name);
$$;

revoke all on function public.hub_ton_price_workify_customers(uuid) from public, anon;
grant execute on function public.hub_ton_price_workify_customers(uuid) to authenticated;
