-- Confirmed Next machine articles point to existing canonical machine projects in Hub.
insert into public.hub_identity_keys(tenant_id,object_id,object_type,identity_type,identity_value,confidence)
select i.tenant_id,i.object_id,i.object_type,'next_machine_article_number',m.article,1
from (values ('M1009','1009'),('M1053','1053')) m(article,project_number)
join public.hub_identity_keys i on i.tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b'::uuid
 and i.identity_type='next_project_number' and i.identity_value=m.project_number and i.confidence=1 and i.object_type='Project'
on conflict do nothing;

create function private.hub_next_machine_followup(
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
  select i.object_id,min(r.project_name) name
  from public.hub_identity_keys i join public.kpi_next_project_register r on r.tenant_id=t and r.project_number=i.identity_value
  where i.tenant_id=t and i.identity_type='next_project_number' and i.confidence=1
  group by i.object_id
 ), source as materialized (
  select r.*,i.machine_id,n.name as machine_name,
   case when r.code ~* '^IN[0-9]' then 'Inhyrda maskiner och redskap'
    when r.code ~* '^(RE|UT|EL)[0-9]' then 'Redskap och tillbehör'
    when r.unit in ('bd','dag','dygn') then 'Dags- och dygnsartiklar'
    when i.machine_id is not null and r.unit='tim' then 'Egna maskiner'
    else 'Maskinartiklar att koppla' end category
  from jsonb_to_recordset(p_rows) as r(sheet text,source_row integer,project text,project_name text,
   work_order text,order_name text,center text,code text,article text,unit text,performed_on date,
   quantity numeric,value numeric)
  left join identities i on i.code=r.code
  left join names n on n.object_id=i.machine_id
  where r.code ~* '^(M|IN|RE|UT|EL)[0-9]' and (p_from is null or r.performed_on>=p_from)
   and (p_to is null or r.performed_on<=p_to)
 ), own as materialized (
  select * from source where category='Egna maskiner'
 ), machines as (
  select machine_id,coalesce(max(machine_name),max(article)) name,array_agg(distinct code order by code) codes,
   count(*) rows,sum(quantity) hours,sum(value) value,
   case when count(quantity)=count(*) and count(value)=count(*) then sum(value)/nullif(sum(quantity),0) end value_per_hour
  from own group by machine_id
 ), months as (
  select to_char(performed_on,'YYYY-MM') month_key,count(*) rows,sum(quantity) hours,sum(value) value,
   case when count(quantity)=count(*) and count(value)=count(*) then sum(value)/nullif(sum(quantity),0) end value_per_hour
  from own where machine_id=p_machine and performed_on is not null group by 1
 ), jobs as (
  select project,work_order,max(project_name) project_name,max(order_name) order_name,
   count(*) rows,sum(quantity) hours,sum(value) value
  from own where machine_id=p_machine group by project,work_order
 ), other_articles as (
  select category,code,article,unit,count(*) rows,sum(quantity) quantity,sum(value) value
  from source where category<>'Egna maskiner' group by category,code,article,unit
 ), details as (
  select sheet,source_row,performed_on,code,article,quantity,value from own
  where machine_id=p_machine and project=p_project and work_order=p_order
 )
 select jsonb_build_object(
  'machines',coalesce((select jsonb_agg(to_jsonb(m) order by m.value desc nulls last,m.name) from machines m),'[]'::jsonb),
  'months',coalesce((select jsonb_agg(to_jsonb(m) order by m.month_key) from months m),'[]'::jsonb),
  'jobs',coalesce((select jsonb_agg(to_jsonb(j) order by j.value desc nulls last,j.project,j.work_order) from jobs j),'[]'::jsonb),
  'others',coalesce((select jsonb_agg(to_jsonb(a) order by a.category,a.value desc nulls last,a.code,a.unit) from other_articles a where p_machine is null),'[]'::jsonb),
  'details',coalesce((select jsonb_agg(to_jsonb(d) order by d.performed_on desc nulls last,d.sheet,d.source_row) from details d),'[]'::jsonb)
 ) into report;
 return report;
end $$;
revoke all on function private.hub_next_machine_followup(uuid,uuid,jsonb,date,date,uuid,text,text) from public,anon,authenticated;
grant execute on function private.hub_next_machine_followup(uuid,uuid,jsonb,date,date,uuid,text,text) to authenticated;

create function public.hub_next_machine_followup(
 t uuid,p_batch uuid,p_rows jsonb,p_from date,p_to date,p_machine uuid,p_project text,p_order text
)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.hub_next_machine_followup(t,p_batch,p_rows,p_from,p_to,p_machine,p_project,p_order)
$$;
revoke all on function public.hub_next_machine_followup(uuid,uuid,jsonb,date,date,uuid,text,text) from public,anon,authenticated;
grant execute on function public.hub_next_machine_followup(uuid,uuid,jsonb,date,date,uuid,text,text) to authenticated;
