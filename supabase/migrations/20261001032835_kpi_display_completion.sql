alter table public.kpi_units drop constraint kpi_units_unit_type_check;
alter table public.kpi_units add constraint kpi_units_unit_type_check check(unit_type in ('vehicle','person','overhead','project','compound'));
create function public.hub_kpi_admin_unit_builder_v2(p_tenant_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI administrator required';end if;
 select jsonb_build_object('candidates',coalesce(jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'registration',(regexp_match(upper(u.name),'\m([A-Z]{3}[0-9]{2}[A-Z0-9])\M'))[1],'projects',u.projects) order by u.name),'[]')) into result
 from public.kpi_units u where u.tenant_id=p_tenant_id and u.origin='next_project_import';return result;
end $$;
revoke all on function public.hub_kpi_admin_unit_builder_v2(uuid) from public,anon;
grant execute on function public.hub_kpi_admin_unit_builder_v2(uuid) to authenticated;
create function public.hub_kpi_unit_report_v2(p_tenant_id uuid,p_from date,p_to date) returns jsonb language sql stable security invoker set search_path='' as $$
 with f as materialized(select * from private.hub_kpi_financial_facts_v1(p_tenant_id,p_from,p_to)), totals as (
 select unit_id,count(*) row_count,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(coalesce(sum(amount) filter(where category='fuel' and kind='cost'),0),2) fuel,round(sum(case when kind='revenue' then amount else -amount end),2) result,0 paid_hours,0 billable_hours from f where unit_id is not null group by unit_id)
 select jsonb_build_object('units',coalesce((select jsonb_agg(to_jsonb(t)) from totals t),'[]'),'quality',jsonb_build_object('unassigned',(select count(*) from f where unit_id is null)),'conflict_rows','[]'::jsonb)
$$;
revoke all on function public.hub_kpi_unit_report_v2(uuid,date,date) from public,anon;
grant execute on function public.hub_kpi_unit_report_v2(uuid,date,date) to authenticated;
create function public.hub_kpi_set_project_group_v2(p_tenant_id uuid,p_project text,p_group_id uuid,p_valid_from date) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI administrator required';end if;
 if nullif(trim(p_project),'') is null or p_valid_from is null or not exists(select 1 from public.kpi_business_groups where id=p_group_id and tenant_id=p_tenant_id and enabled) then raise exception 'Invalid project/group/date';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||p_project,0));
 if exists(select 1 from public.kpi_project_business_groups where tenant_id=p_tenant_id and project_reference=p_project and coalesce(valid_from,'2000-01-01')>=p_valid_from) then raise exception 'Start date must follow existing history';end if;
 update public.kpi_project_business_groups set valid_to=p_valid_from-1 where tenant_id=p_tenant_id and project_reference=p_project and (valid_to is null or valid_to>=p_valid_from);
 insert into public.kpi_project_business_groups(tenant_id,project_reference,business_group_id,valid_from,source) values(p_tenant_id,p_project,p_group_id,p_valid_from,'kpi_admin_dated') returning id into result;return result;
end $$;
revoke all on function public.hub_kpi_set_project_group_v2(uuid,text,uuid,date) from public,anon;
grant execute on function public.hub_kpi_set_project_group_v2(uuid,text,uuid,date) to authenticated;
