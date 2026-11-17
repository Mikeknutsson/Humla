-- Summarize one verified resource export at a time. Source rows are report evidence.
create function private.hub_workshop_resource_report(
 t uuid,p_batch uuid,p_rows jsonb,p_from date,p_to date,p_center text,p_review boolean,
 p_project text,p_order text,p_page integer
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or public.hub_has_permission(t,'kpi.read') is not true then
  raise exception 'Access denied' using errcode='42501';
 end if;
 if not exists(select 1 from public.kpi_import_batches b where b.tenant_id=t and b.id=p_batch and b.data_kind='next_articles' and b.status='completed') then
  raise exception 'Resource export not found' using errcode='22023';
 end if;
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)>30000
  or p_from>p_to or p_review is null or (p_project is null)<>(p_order is null)
  or p_page is null or p_page not between 0 and 1000 then
  raise exception 'Invalid resource report' using errcode='22023';
 end if;
 with source as materialized (
  select *,coalesce(nullif(center,''),'Kostnadsställe saknas') as center_label,
   (invoiced is false and billable is true) as open_amount,
   case when value is null then 'Värde saknas'
    when actual_cost is null or (actual_cost=0 and value<>0) then 'Kostnad saknas eller är noll'
    when invoiced is null or billable is null then 'Fakturastatus behöver kontrolleras' end as deviation
  from jsonb_to_recordset(p_rows) as r(sheet text,source_row integer,project text,project_name text,
   work_order text,order_name text,center text,code text,article text,unit text,performed_on date,
   quantity numeric,value numeric,actual_cost numeric,invoiced boolean,billable boolean,invoice_number text)
 ), period as materialized (
  select * from source where (p_from is null or performed_on>=p_from) and (p_to is null or performed_on<=p_to)
 ), scoped as materialized (
  select * from period where p_center is null or center_label=p_center
 ), visible as materialized (
  select * from scoped where not p_review or open_amount or deviation is not null
 ), totals as (
  select count(*) rows,count(distinct (project,work_order)) filter(where project<>'' and work_order<>'') orders,
   sum(value) value,sum(actual_cost) cost,sum(quantity) filter(where unit='tim') hours,sum(value) filter(where unit<>'' and unit<>'tim') material,
   sum(value) filter(where open_amount) pending,count(*) filter(where open_amount) pending_rows,
   count(*) filter(where deviation is not null) deviations,count(*) filter(where performed_on is null) undated
  from scoped
 ), centers as (
  select center_label center,count(*) rows,sum(value) value,sum(actual_cost) cost,
   sum(quantity) filter(where unit='tim') hours,sum(value) filter(where unit<>'' and unit<>'tim') material,sum(value) filter(where open_amount) pending
  from period group by center_label
 ), months as (
  select to_char(performed_on,'YYYY-MM') as month_key,sum(value) value,sum(actual_cost) cost,
   sum(quantity) filter(where unit='tim') hours,sum(value) filter(where unit<>'' and unit<>'tim') material,sum(value) filter(where open_amount) pending
  from scoped where performed_on is not null group by 1
 ), orders as (
  select center_label center,project,work_order,max(project_name) project_name,max(order_name) order_name,
   count(*) rows,sum(value) value,sum(actual_cost) cost,sum(quantity) filter(where unit='tim') hours,sum(value) filter(where unit<>'' and unit<>'tim') material,
   sum(value) filter(where open_amount) pending,count(*) filter(where deviation is not null) deviations
  from visible where p_project is null group by center_label,project,work_order
  order by case when p_review then coalesce(sum(value) filter(where open_amount),0) else coalesce(sum(value),0) end desc,
   center_label,project,work_order offset p_page*50 limit 51
 ), details as (
  select * from visible where project=p_project and work_order=p_order
  order by performed_on desc nulls last,sheet,source_row offset p_page*50 limit 51
 )
 select jsonb_build_object(
  'totals',(select to_jsonb(totals) from totals),
  'centers',coalesce((select jsonb_agg(to_jsonb(c) order by c.value desc nulls last,c.center) from centers c),'[]'::jsonb),
  'months',coalesce((select jsonb_agg(to_jsonb(m) order by m.month_key) from months m),'[]'::jsonb),
  'orders',coalesce((select jsonb_agg(to_jsonb(o) order by case when p_review then coalesce(o.pending,0) else coalesce(o.value,0) end desc,o.center,o.project,o.work_order) from orders o),'[]'::jsonb),
  'details',coalesce((select jsonb_agg(to_jsonb(d) order by d.performed_on desc nulls last,d.sheet,d.source_row) from details d),'[]'::jsonb)
 ) into result;
 return result;
end $$;
revoke all on function private.hub_workshop_resource_report(uuid,uuid,jsonb,date,date,text,boolean,text,text,integer) from public,anon,authenticated;
grant execute on function private.hub_workshop_resource_report(uuid,uuid,jsonb,date,date,text,boolean,text,text,integer) to authenticated;

create function public.hub_workshop_resource_report(
 t uuid,p_batch uuid,p_rows jsonb,p_from date,p_to date,p_center text,p_review boolean,
 p_project text,p_order text,p_page integer
)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.hub_workshop_resource_report(t,p_batch,p_rows,p_from,p_to,p_center,p_review,p_project,p_order,p_page)
$$;
revoke all on function public.hub_workshop_resource_report(uuid,uuid,jsonb,date,date,text,boolean,text,text,integer) from public,anon,authenticated;
grant execute on function public.hub_workshop_resource_report(uuid,uuid,jsonb,date,date,text,boolean,text,text,integer) to authenticated;
