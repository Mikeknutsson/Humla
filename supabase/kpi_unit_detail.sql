create function public.kpi_unit_detail(p_tenant_id uuid,p_unit_id uuid,p_from date,p_to date,p_grain text default 'month',p_page integer default 0)
returns jsonb language plpgsql stable security invoker set search_path=public as $$
declare output jsonb;
begin
 if not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'Behörighet saknas'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 or p_page<0 or p_page>100000 or p_grain not in ('year','month','week','day') then raise exception 'Ogiltig period'; end if;
 if not exists(select 1 from public.kpi_units where id=p_unit_id and tenant_id=p_tenant_id) then raise exception 'Enheten saknas'; end if;
with base as (
 select r.*, b.file_name, am.calculation_role mapped_role, am.include_in_vehicle_result,
 case when r.data_kind='cost' then coalesce(am.calculation_role,'unmapped') else r.data_kind end role
 from public.kpi_import_rows r
 join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 left join lateral (
  select m.calculation_role,m.include_in_vehicle_result from public.kpi_account_mappings m
  where r.data_kind='cost' and m.tenant_id=r.tenant_id and m.enabled
   and (case when trim(r.account) ~ '^[0-9]{1,8}$' then trim(r.account)::integer end) between m.account_from and m.account_to
   and r.occurred_on>=m.valid_from and (m.valid_to is null or r.occurred_on<=m.valid_to)
  order by m.priority desc,(m.account_to-m.account_from),m.valid_from desc,m.created_at desc limit 1
 ) am on true
 where r.tenant_id=p_tenant_id and r.occurred_on between p_from and p_to
  and b.status in ('completed','needs_review') and public.hub_has_permission(p_tenant_id,'kpi.read')
), matched as (
 select b.*, hit.ids from base b
 cross join lateral (
  select array_agg(u.id) ids from public.kpi_units u
  where u.tenant_id=b.tenant_id and u.enabled and b.occurred_on>=u.valid_from
   and (u.valid_to is null or b.occurred_on<=u.valid_to)
   and (upper(trim(b.project_reference))=any(u.projects)
     or upper(regexp_replace(b.vehicle_registration,'[[:space:]-]','','g'))=any(u.registrations)
     or upper(trim(b.employee_number))=any(u.employees))
 ) hit
), accepted as (
 select m.*,ids[1] unit_id,u.unit_type from matched m join public.kpi_units u on u.id=m.ids[1] and u.tenant_id=m.tenant_id where cardinality(ids)=1 and is_valid
  and role not in ('unmapped','exclude')
) , selected as (
 select a.*,
 case when role='revenue' then coalesce(amount,0) else 0 end revenue,
 case when role='cost' and (unit_type<>'vehicle' or coalesce(include_in_vehicle_result,true)) then coalesce(amount,0) else 0 end cost,
 case when role='fuel' and (unit_type<>'vehicle' or coalesce(include_in_vehicle_result,true)) then coalesce(amount,0) else 0 end fuel
 from accepted a where unit_id=p_unit_id
), grouped as (
 select s.*, case p_grain
 when 'year' then make_date(extract(year from occurred_on)::int-case when occurred_on<make_date(extract(year from occurred_on)::int,coalesce(k.financial_year_start_month,9),coalesce(k.financial_year_start_day,1)) then 1 else 0 end,coalesce(k.financial_year_start_month,9),coalesce(k.financial_year_start_day,1))
 when 'month' then date_trunc('month',occurred_on)::date
 when 'week' then date_trunc('week',occurred_on)::date
 when 'day' then occurred_on end period_start
 from selected s left join public.kpi_settings k on k.tenant_id=s.tenant_id
), periods as (
 select period_start,
 greatest(period_start,p_from) range_start,
 least(p_to,(case p_grain when 'year' then period_start+interval '1 year' when 'month' then period_start+interval '1 month' when 'week' then period_start+interval '1 week' else period_start+interval '1 day' end)::date-1) range_end,
 count(*) row_count,sum(revenue) revenue,sum(cost) cost,sum(fuel) fuel,sum(revenue-cost-fuel) result
 from grouped group by period_start
)
select jsonb_build_object(
 'periods',coalesce((select jsonb_agg(to_jsonb(p) order by period_start) from periods p),'[]'),
 'total_rows',(select count(*) from selected),
 'totals',(select jsonb_build_object('revenue',coalesce(sum(revenue),0),'cost',coalesce(sum(cost),0),'fuel',coalesce(sum(fuel),0),'result',coalesce(sum(revenue-cost-fuel),0)) from selected),
 'rows',coalesce((select jsonb_agg(to_jsonb(d)) from (select id,batch_id,row_number,occurred_on,description,project_reference,vehicle_registration,employee_number,account,amount,revenue,cost,fuel,revenue-cost-fuel result,file_name,source_data,allocation from selected order by occurred_on,id limit 50 offset greatest(0,p_page)*50)d),'[]'),
 'held_rows',(select count(*) from matched where p_unit_id=any(ids) and (cardinality(ids)>1 or not is_valid or role in ('unmapped','exclude')))
) into output;
return output;
end $$;
revoke all on function public.kpi_unit_detail(uuid,uuid,date,date,text,integer) from public,anon;
grant execute on function public.kpi_unit_detail(uuid,uuid,date,date,text,integer) to authenticated;
