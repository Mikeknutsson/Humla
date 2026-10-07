create or replace function public.hub_kpi_attendance_connection_v1(p_tenant_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $f$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 return jsonb_build_object(
 'settings',(select to_jsonb(s)-'updated_by' from public.kpi_attendance_settings s where tenant_id=p_tenant_id),
 'salary_resources',(select count(*) from public.hub_transpa_salary_resources where tenant_id=p_tenant_id),
 'last_received',(select max(received_at) from public.hub_transpa_salary_resources where tenant_id=p_tenant_id),
 'pending_events',(select count(*) from public.hub_transpa_salary_events where tenant_id=p_tenant_id and status in ('pending','retry','processing')),
 'codes',coalesce((select jsonb_agg(to_jsonb(c) order by pay_type_code) from(select r.pay_type_code,count(*) rows,m.category,m.unit from public.hub_transpa_time_rows r left join public.kpi_transpa_attendance_codes m on m.tenant_id=r.tenant_id and m.pay_type_code=r.pay_type_code where r.tenant_id=p_tenant_id group by r.pay_type_code,m.category,m.unit)c),'[]'::jsonb));
end $f$;
revoke all on function public.hub_kpi_attendance_connection_v1(uuid) from public,anon;
grant execute on function public.hub_kpi_attendance_connection_v1(uuid) to authenticated;