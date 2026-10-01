create or replace function private.hub_kpi_units_at_date_v1(p_tenant_id uuid,p_date date) returns setof public.kpi_units
language sql stable security definer set search_path='' as $$
 select (jsonb_populate_record(null::public.kpi_units,to_jsonb(u)||coalesce(v.payload,'{}')||case when v.id is not null then jsonb_build_object('valid_from',v.valid_from,'valid_to',v.valid_to) else '{}' end)).*
 from public.kpi_units u left join public.kpi_unit_periods v on v.unit_id=u.id and v.tenant_id=u.tenant_id and v.valid_from<=p_date and (v.valid_to is null or v.valid_to>=p_date)
 where u.tenant_id=p_tenant_id and u.origin in ('manual','manual_builder') and auth.uid() is not null and public.hub_has_permission(p_tenant_id,'kpi.read')
 and (v.id is not null or (not exists(select 1 from public.kpi_unit_periods x where x.unit_id=u.id) and u.valid_from<=p_date and (u.valid_to is null or u.valid_to>=p_date)))
$$;
revoke all on function private.hub_kpi_units_at_date_v1(uuid,date) from public,anon;
grant execute on function private.hub_kpi_units_at_date_v1(uuid,date) to authenticated;
