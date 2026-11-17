create or replace function private.hub_next_machine_followup(
 t uuid,p_batch uuid,p_rows jsonb,p_from date,p_to date,p_machine uuid,p_project text,p_order text
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare report jsonb;
begin
 if auth.uid() is null or public.hub_has_permission(t,'kpi.read') is not true then
  raise exception 'Access denied' using errcode='42501';
 end if;
 if not exists(select 1 from public.kpi_import_batches b where b.tenant_id=t and b.id=p_batch and b.data_kind='next_articles' and b.status='completed') then
  raise exception 'Resource export not found' using errcode='22023';
 end if;
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)>30000 or p_from>p_to
  or (p_project is null)<>(p_order is null) or (p_project is not null and p_machine is null) then
  raise exception 'Invalid machine report' using errcode='22023';
 end if;
 with identities as (
  select i.identity_value as code,(array_agg(distinct i.object_id))[1] as machine_id
  from public.hub_identity_keys i join public.hub_objects o on o.id=i.object_id and o.tenant_id=t and o.object_type='Project'
  where i.tenant_id=t and i.identity_type='next_machine_article_number' and i.confidence=1 and i.object_type='Project'
  group by i.identity_value having count(distinct i.object_id)=1
 ), names as (
  select i.object_id,min(r.project_name) name, string_agg(distinct r.project_number, ', ' order by r.project_number) machine_reference
  from public.hub_identity_keys i join public.kpi_next_project_register r on r.tenant_id=t and r.project_number=i.identity_value
  where i.tenant_id=t and i.identity_type='next_project_number' and i.confidence=1
  group by i.object_id
 ), source as materialized (
  select r.*,i.machine_id,n.name as machine_name,n.machine_reference,
   case when classification.group_name='entreprenad' then 'Intern entreprenad'
    when classification.group_name in ('maskinuthyrning / bemanning','extern uthyrning')
     and nullif(btrim(r.customer),'') is not null
     and btrim(r.customer) !~* '^elleholms([[:space:]]|$)'
    then 'Extern uthyrning'
    else 'Ej klassificerat' end usage,
   case when r.code ~* '^IN[0-9]' then 'Inhyrda maskiner och redskap'
    when r.code ~* '^(RE|UT|EL)[0-9]' then 'Redskap och tillbehör'
    when r.unit in ('bd','dag','dygn') then 'Dags- och dygnsartiklar'
    when i.machine_id is not null and r.unit='tim' then 'Egna maskiner'
    else 'Maskinartiklar att koppla' end category
  from jsonb_to_recordset(p_rows) as r(sheet text,source_row integer,project text,project_name text,
   work_order text,order_name text,center text,code text,article text,unit text,performed_on date,
   quantity numeric,value numeric,performed_by text,employee_number text,customer text)
  left join identities i on i.code=r.code
  left join names n on n.object_id=i.machine_id
  left join lateral (
   select min(lower(btrim(c.business_group))) group_name
   from public.kpi_project_classification_periods c
   where i.machine_id is not null and c.tenant_id=t and c.project_reference=r.project
    and c.valid_from<=r.performed_on and (c.valid_to is null or c.valid_to>=r.performed_on)
   having count(*)=count(nullif(btrim(c.business_group),'')) and count(distinct lower(btrim(c.business_group)))=1
  ) classification on true
  where r.code ~* '^(M|IN|RE|UT|EL)[0-9]' and (p_from is null or r.performed_on>=p_from)
   and (p_to is null or r.performed_on<=p_to)
 ), own as materialized (
  select * from source where category='Egna maskiner'
 ), machines as (
  select machine_id,max(machine_reference) machine_reference,coalesce(max(machine_name),max(article)) name,array_agg(distinct code order by code) codes,
   count(*) rows,sum(quantity) hours,sum(value) value,
   case when count(quantity)=count(*) and count(value)=count(*) then sum(value)/nullif(sum(quantity),0) end value_per_hour
  from own group by machine_id
 ), usage_totals as (
  select machine_id,usage,count(*) rows,sum(quantity) hours,sum(value) value
  from own group by machine_id,usage
 ), usage_by_machine as (
  select machine_id,jsonb_object_agg(usage,jsonb_build_object('rows',rows,'hours',hours,'value',value)) buckets
  from usage_totals group by machine_id
 ), machine_orders as (
  select distinct machine_id,project,work_order from own where nullif(work_order,'') is not null
 ), order_examples as (
  select machine_id,count(*) order_count,(array_agg(concat_ws(' / ',nullif(project,''),'AO '||work_order) order by project,work_order))[1:3] order_refs
  from machine_orders group by machine_id
 ), driver_names as (
  select lower(btrim(performed_by)) name,min(nullif(btrim(employee_number),'')) employee_number
  from own where machine_id=p_machine and nullif(btrim(performed_by),'') is not null
  group by lower(btrim(performed_by)) having count(distinct nullif(btrim(employee_number),''))=1
 ), driver_rows as (
  select o.*,coalesce(nullif(btrim(o.performed_by),''),case when nullif(btrim(o.employee_number),'') is not null then 'Namn saknas i NeXT' else 'Förare saknas i NeXT' end) driver_name,
   coalesce('id:'||coalesce(nullif(btrim(o.employee_number),''),d.employee_number),'name:'||nullif(lower(btrim(o.performed_by)),''), 'unknown') driver_key
  from own o left join driver_names d on d.name=lower(btrim(o.performed_by))
  where o.machine_id=p_machine
 ), drivers as (
  select driver_key,coalesce(max(driver_name) filter(where driver_name not in ('Namn saknas i NeXT','Förare saknas i NeXT')),max(driver_name)) name,
   count(*) rows,sum(quantity) hours,count(distinct (project,work_order)) filter(where nullif(work_order,'') is not null) orders
  from driver_rows group by driver_key
 ), months as (
  select to_char(performed_on,'YYYY-MM') month_key,count(*) rows,sum(quantity) hours,sum(value) value,
   case when count(quantity)=count(*) and count(value)=count(*) then sum(value)/nullif(sum(quantity),0) end value_per_hour
  from own where machine_id=p_machine and performed_on is not null group by 1
 ), jobs as (
  select project,work_order,usage,max(project_name) project_name,max(order_name) order_name,
   count(*) rows,sum(quantity) hours,sum(value) value,array_agg(distinct driver_name order by driver_name) drivers
  from driver_rows group by project,work_order,usage
 ), other_articles as (
  select category,code,article,unit,count(*) rows,sum(quantity) quantity,sum(value) value
  from source where category<>'Egna maskiner' group by category,code,article,unit
 ), details as (
  select sheet,source_row,performed_on,code,article,quantity,value,driver_name,usage from driver_rows
  where project=p_project and work_order=p_order
 )
 select jsonb_build_object(
  'machines',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('order_count',coalesce(o.order_count,0),'order_refs',coalesce(o.order_refs,array[]::text[]),'usage',coalesce(u.buckets,'{}'::jsonb)) order by m.value desc nulls last,m.name) from machines m left join order_examples o using(machine_id) left join usage_by_machine u using(machine_id)),'[]'::jsonb),
  'drivers',coalesce((select jsonb_agg(to_jsonb(d)-'driver_key' order by d.hours desc nulls last,d.name,d.driver_key) from drivers d),'[]'::jsonb),
  'months',coalesce((select jsonb_agg(to_jsonb(m) order by m.month_key) from months m),'[]'::jsonb),
  'jobs',coalesce((select jsonb_agg(to_jsonb(j) order by j.value desc nulls last,j.project,j.work_order,j.usage) from jobs j),'[]'::jsonb),
  'others',coalesce((select jsonb_agg(to_jsonb(a) order by a.category,a.value desc nulls last,a.code,a.unit) from other_articles a where p_machine is null),'[]'::jsonb),
  'details',coalesce((select jsonb_agg(to_jsonb(d) order by d.performed_on desc nulls last,d.sheet,d.source_row) from details d),'[]'::jsonb)
 ) into report;
 return report;
end $$;
