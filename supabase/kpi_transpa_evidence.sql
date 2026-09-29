-- Restricted aggregate bridge: no raw HR payload or credentials exposed to KPI clients.
create function private.kpi_transpa_evidence(p_tenant_id uuid,p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 then raise exception 'Ogiltig period';end if;
 with reports as (
 select external_id,payload->>'employeeId' employee_id,payload->>'status' status,
 ((payload->>'startDateTime')::timestamptz at time zone 'Europe/Stockholm')::date report_date,
 case when payload->>'adjustedWorkTimeInMinutes' ~ '^\d+$' then (payload->>'adjustedWorkTimeInMinutes')::numeric/60 end hours,
 payload->'partsOfDay' parts
 from public.hub_transpa_entities where tenant_id=p_tenant_id and entity_type='time_report'
 ), scoped as(select * from reports where report_date between p_from and p_to), daily as (
 select report_date,count(*) reports,count(distinct employee_id) employees,round(sum(hours),2) hours,
 round(coalesce(sum(hours) filter(where status='approved'),0),2) approved_hours
 from scoped group by report_date
 ) select jsonb_build_object(
 'reports',(select count(*) from scoped),'employees',(select count(distinct employee_id) from scoped),
 'hours',(select round(coalesce(sum(hours),0),2) from scoped),
 'approved_hours',(select round(coalesce(sum(hours) filter(where status='approved'),0),2) from scoped),
 'unapproved_reports',(select count(*) from scoped where status is distinct from 'approved'),
 'vehicle_references',(select count(distinct p->>'vehicleId') from scoped cross join lateral jsonb_array_elements(case when jsonb_typeof(parts)='array' then parts else '[]' end)p),
 'persons',(select count(*) from public.hub_transpa_persons where tenant_id=p_tenant_id),
 'linked_persons',(select count(humla_person_object_id) from public.hub_transpa_persons where tenant_id=p_tenant_id),
 'salary_records',(select count(*) from public.hub_transpa_entities where tenant_id=p_tenant_id and entity_type='salary'),
 'daily',coalesce((select jsonb_agg(to_jsonb(d) order by report_date) from daily d),'[]'),
 'latest_sync',(select jsonb_build_object('started_at',started_at,'completed_at',completed_at,'status',status,'fetched',fetched_count,'errors',error_count) from public.hub_transpa_sync_runs where tenant_id=p_tenant_id and 'timeReports'=any(entity_types) order by started_at desc limit 1)
 ) into result;
 return result;
end $$;
revoke all on function private.kpi_transpa_evidence(uuid,date,date) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.kpi_transpa_evidence(uuid,date,date) to authenticated;
create function public.kpi_transpa_evidence(p_tenant_id uuid,p_from date,p_to date) returns jsonb language sql stable security invoker set search_path=pg_catalog as $$select private.kpi_transpa_evidence(p_tenant_id,p_from,p_to)$$;
revoke all on function public.kpi_transpa_evidence(uuid,date,date) from public,anon;
grant execute on function public.kpi_transpa_evidence(uuid,date,date) to authenticated;
