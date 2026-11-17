-- Attach reviewed NeXT machine articles to existing canonical project objects.
-- Generic hired machines, accessories and conflicting model names require their own review.
insert into public.hub_identity_keys (tenant_id,object_id,object_type,identity_type,identity_value,confidence)
select i.tenant_id,i.object_id,'Project','next_machine_article_number',reviewed.article,1
from (values
  ('M1006','1006'),
  ('M1011','1011'),
  ('M1012','1012'),
  ('M1012D','1012'),
  ('M1031','1031'),
  ('M1039','1039'),
  ('M1040','1040'),
  ('M1041','1041'),
  ('M1041D','1041'),
  ('M1042','1042'),
  ('M1042D','1042'),
  ('M1046','1046'),
  ('M1048','1048'),
  ('M1050','1050'),
  ('M1051','1051'),
  ('M1052','1052'),
  ('M1054D','1054'),
  ('M1055','1055'),
  ('M1057','1057'),
  ('M1057D','1057'),
  ('M1058','1058'),
  ('M1059','1059'),
  ('M1060','1060'),
  ('M1061','1061'),
  ('M1062','1062'),
  ('M1063','1063'),
  ('M1064','1064'),
  ('M1065','1065'),
  ('M1066','1066'),
  ('M1066D','1066'),
  ('M1067','1067'),
  ('M1069','1069'),
  ('M1071','1071'),
  ('M1071 DAG','1071'),
  ('M1072','1072'),
  ('M1073','1073'),
  ('M1074','1074'),
  ('M1076','1076'),
  ('M1078','1078'),
  ('M1080','1080'),
  ('M1081','1081'),
  ('M1083','1083'),
  ('M1084','1084'),
  ('M1084D','1084'),
  ('M1085','1085'),
  ('M1086','1086'),
  ('M1087','1087'),
  ('M1088','1088'),
  ('M1088 DAG','1088'),
  ('M1089','1089'),
  ('M1091','1091'),
  ('M1092','1092')
) reviewed(article,project)
join public.hub_identity_keys i on i.identity_type='next_project_number' and i.identity_value=reviewed.project
 and i.object_type='Project' and i.confidence=1
join public.hub_objects o on o.tenant_id=i.tenant_id and o.id=i.object_id and o.object_type='Project'
join public.kpi_next_project_register r on r.tenant_id=i.tenant_id and r.project_number=reviewed.project
where i.tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b'
 and (r.project_category='Maskiner' or
      (r.project_number='1086' and r.project_name='Volvo EWR130') or
      (r.project_number='1088' and lower(r.project_name)='bandgrävaren bobcat e27z'))
on conflict (tenant_id,identity_type,identity_value) do nothing;

create or replace function private.hub_next_machine_followup(
 t uuid,p_batch uuid,p_rows jsonb,p_from date,p_to date,p_machine uuid,p_project text,p_order text,p_months integer[]
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
 with active_generation as (
  select active_generation id from private.hub_kpi_report_state where tenant_id=t
 ), batch_capacity as (
  select to_char(d,'YYYY-MM') month_key,count(*) *
   coalesce((select vehicle_capacity_hours_per_day from public.kpi_settings where tenant_id=t),8) available_hours
  from public.kpi_import_batches b
  cross join lateral generate_series(greatest(p_from,b.period_start)::timestamp,
   least(p_to,b.period_end)::timestamp,interval '1 day') d
  where b.tenant_id=t and b.id=p_batch and b.period_start is not null and b.period_end is not null
   and extract(isodow from d) between 1 and 5 and not public.hub_is_swedish_public_holiday(d::date)
   and (p_months is null or extract(month from d)=any(p_months))
  group by 1
 ), identities as (
  select i.identity_value as code,(array_agg(distinct i.object_id))[1] as machine_id
  from public.hub_identity_keys i join public.hub_objects o on o.id=i.object_id and o.tenant_id=t and o.object_type='Project'
  where i.tenant_id=t and i.identity_type='next_machine_article_number' and i.confidence=1 and i.object_type='Project'
  group by i.identity_value having count(distinct i.object_id)=1
 ), asset_projects as (
  select i.identity_value project,(array_agg(distinct i.object_id))[1] machine_id
  from public.hub_identity_keys i join (select distinct machine_id from identities) m on m.machine_id=i.object_id
  where i.tenant_id=t and i.object_type='Project' and i.identity_type='next_project_number' and i.confidence=1
  group by i.identity_value having count(distinct i.object_id)=1
 ), names as (
  select i.object_id,min(r.project_name) name, string_agg(distinct r.project_number, ', ' order by r.project_number) machine_reference
  from public.hub_identity_keys i join public.kpi_next_project_register r on r.tenant_id=t and r.project_number=i.identity_value
  where i.tenant_id=t and i.identity_type='next_project_number' and i.confidence=1
  group by i.object_id
 ), source as materialized (
  select r.*,i.machine_id,n.name as machine_name,n.machine_reference,
   case when classification.group_name='entreprenad' then 'Intern entreprenad'
    when coalesce(classification.group_name,first_rental.group_name) in ('maskinuthyrning / bemanning','extern uthyrning')
     and nullif(btrim(r.customer),'') is not null
     and btrim(r.customer) !~* '^elleholms([[:space:]]|$)'
    then 'Extern uthyrning'
    else 'Ej klassificerat' end usage,
   case when r.code ~* '^IN[0-9]' then 'Inhyrda maskiner och redskap'
    when r.code ~* '^(RE|UT|EL)[0-9]' then 'Redskap och tillbehör'
    when i.machine_id is not null and r.unit in ('tim','bd','dag','dygn') then 'Egna maskiner'
    when r.unit in ('bd','dag','dygn') then 'Dags- och dygnsartiklar'
    else 'Maskinartiklar att koppla' end category
  from jsonb_to_recordset(p_rows) as r(sheet text,source_row integer,project text,project_name text,
   work_order text,order_name text,center text,code text,article text,unit text,performed_on date,
   quantity numeric,value numeric,performed_by text,employee_number text,customer text,invoiced boolean)
  left join identities i on i.code=r.code
  left join names n on n.object_id=i.machine_id
  left join lateral (
   select min(lower(btrim(c.business_group))) group_name
   from public.kpi_project_classification_periods c
   where i.machine_id is not null and c.tenant_id=t and c.project_reference=r.project
    and c.valid_from<=r.performed_on and (c.valid_to is null or c.valid_to>=r.performed_on)
   having count(*)=count(nullif(btrim(c.business_group),'')) and count(distinct lower(btrim(c.business_group)))=1
  ) classification on true
  left join lateral (
   select lower(btrim(reg.project_category)) group_name
   from public.kpi_next_project_register reg
   where classification.group_name is null and i.machine_id is not null
    and reg.tenant_id=t and reg.project_number=r.project
    and lower(btrim(reg.project_category)) in ('maskinuthyrning / bemanning','extern uthyrning')
    and exists (
     select 1 from public.kpi_project_classification_periods c
     where c.tenant_id=t and c.project_reference=r.project
     group by c.project_reference
     having r.performed_on<min(c.valid_from) and bool_and(
      coalesce(lower(btrim(c.business_group)) in ('maskinuthyrning / bemanning','extern uthyrning'),false)
     )
    )
  ) first_rental on true
  where r.code ~* '^(M|IN|RE|UT|EL)[0-9]' and (p_from is null or r.performed_on>=p_from)
   and (p_to is null or r.performed_on<=p_to)
   and (p_months is null or extract(month from r.performed_on)=any(p_months))
 ), own as materialized (
  select * from source where category='Egna maskiner'
 ), dated_costs as materialized (
  select f.* from private.hub_kpi_report_facts_v1 f
  join active_generation g on g.id=f.generation_id
  where f.tenant_id=t and f.kind='cost'
   and (p_from is null or f.occurred_on>=p_from) and (p_to is null or f.occurred_on<=p_to)
   and (p_months is null or extract(month from f.occurred_on)=any(p_months))
   and f.source='TransPA'
 ), asset_costs as materialized (
  select a.machine_id,f.occurred_on,f.amount,f.account,f.source,
   case when f.source='NEXT' and f.account in ('5510','5511','5633')
     and coalesce(nullif(f.original->>'Verifikationstext',''),f.description,'')
      ~* '^(kreditering[[:space:]]+)?intern[[:space:]]+ao[[:space:]]+[0-9]{4}-[0-9]{2}'
    then 'internal_ao'
    when f.source='NEXT' and f.account in ('5633','5637','5638','5520','5511','5461','4630') then 'service_repair'
    when f.source='NEXT' and f.account='5632' then 'fixed'
    when f.source='NEXT' and f.account in ('5631','5360','5611') then 'fuel'
    when f.source='NEXT' and f.account in ('4052','4441') then 'hired'
    when f.source='NEXT' and f.account='4011' then 'material'
    when f.source='NEXT' and f.account='4600' and f.original->>'Kontobeskrivning' ilike 'Transport%' then 'transport'
    when f.category='depreciation' or f.account ~ '^78[0-9]{2}$' then 'depreciation'
    when f.account ~ '^7[0-6][0-9]{2}$' and f.category is distinct from 'depreciation'
    then 'personnel' else coalesce(f.category,'other') end category
  from private.hub_kpi_report_facts_v1 f join active_generation g on g.id=f.generation_id
  join asset_projects a on a.project=f.project
  where f.tenant_id=t and f.kind='cost' and f.source not in ('TransPA','Preliminär arbetskostnad','Overhead','Verkstadsschablon')
   and (p_from is null or f.occurred_on>=date_trunc('month',p_from)::date)
   and (p_to is null or f.occurred_on<date_trunc('month',p_to)+interval '1 month')
   and (p_months is null or extract(month from f.occurred_on)=any(p_months))
   -- NeXT posts the same resource time as monthly bookkeeping summaries.
   and not (f.source='NEXT' and coalesce(f.account,'') ~ '^7[0-6][0-9]{2}$'
    and (coalesce(f.original->>'Verifikationstext','') ~* '^arbetstid[[:space:]]+[0-9]{4}-[0-9]{2}'
      or coalesce(f.description,'') ~* '^arbetstid[[:space:]]+[0-9]{4}-[0-9]{2}'))
 ), scoped_booked as materialized (
  select * from asset_costs
  where (p_from is null or occurred_on>=p_from) and (p_to is null or occurred_on<=p_to)
 ), booked as (
  select machine_id,category,sum(amount) amount
  from scoped_booked group by 1,2
 ), booked_by_machine as (
  select machine_id,sum(amount) filter(where category<>'internal_ao') booked_cost,
   sum(amount) filter(where category='internal_ao') internal_ao,
   jsonb_object_agg(category,amount) filter(where category<>'internal_ao') categories
  from booked group by machine_id
 ), booked_accounts as (
  select category,account,source,sum(amount) amount,count(*) row_count
  from scoped_booked where machine_id=p_machine group by 1,2,3
 ), person_keys as materialized (
  select k.identity_type,upper(btrim(k.identity_value)) key,(array_agg(distinct k.object_id))[1] person
  from public.hub_identity_keys k join public.hub_objects o on o.tenant_id=t and o.id=k.object_id and o.object_type='Person'
  where k.tenant_id=t and k.object_type='Person' and k.confidence=1
   and k.identity_type in ('next_person_name','next_employee_number','transpa_employee_id')
  group by 1,2 having count(distinct k.object_id)=1
 ), machine_hours as materialized (
  select coalesce(en.person,nm.person) person,s.performed_on work_date,nullif(s.project,'') project,s.work_order,s.usage,
   case when s.category='Egna maskiner' then s.machine_id end machine_id,sum(s.quantity) hours
  from source s
  left join person_keys en on en.identity_type='next_employee_number' and en.key=upper(btrim(s.employee_number))
  left join person_keys nm on nm.identity_type='next_person_name' and nm.key=upper(btrim(s.performed_by))
  where s.category in ('Egna maskiner','Maskinartiklar att koppla','Inhyrda maskiner och redskap')
   and s.unit='tim' and s.quantity is not null
   and coalesce(en.person,nm.person) is not null and (en.person is null or nm.person is null or en.person=nm.person)
  group by 1,2,3,4,5,6 having sum(s.quantity)>0
 ), transpa_reports as (
  select k.person,f.occurred_on work_date,f.original->>'time_report_id' report_id,
   max(nullif(coalesce(f.original->>'_humla_original_project',f.project),'')) project,
   max(case when f.original->>'work_hours' ~ '^[0-9]+([.][0-9]+)?$' then (f.original->>'work_hours')::numeric end) hours,
   sum(f.amount) amount
  from dated_costs f join person_keys k on k.identity_type='transpa_employee_id' and k.key=upper(btrim(f.original->>'employee_id'))
  where f.source='TransPA' and f.category='personnel' and nullif(f.original->>'time_report_id','') is not null
   and exists(select 1 from machine_hours m where m.person=k.person and m.work_date=f.occurred_on)
  group by 1,2,3
  having count(distinct nullif(coalesce(f.original->>'_humla_original_project',f.project),''))<=1
 ), time_pools as (
  select person,work_date,project,sum(hours) hours,sum(amount) amount from transpa_reports
  where hours>0 group by 1,2,3
 ), allocated as (
  select m.machine_id,m.work_date,m.project,m.work_order,m.usage,
   sum(m.hours*least(1,p.hours/eligible.hours)) hours,
   sum(p.amount*m.hours/greatest(p.hours,eligible.hours)) amount
  from time_pools p
  join lateral (
   select sum(h.hours) hours from machine_hours h where h.person=p.person and h.work_date=p.work_date
    and (h.project=p.project or (p.project is null and not exists (
     select 1 from time_pools known where known.person=p.person and known.work_date=p.work_date and known.project=h.project
    )))
  ) eligible on eligible.hours>0
  join machine_hours m on m.person=p.person and m.work_date=p.work_date and (
   m.project=p.project or (p.project is null and not exists (
    select 1 from time_pools known where known.person=p.person and known.work_date=p.work_date and known.project=m.project
   ))
  )
  where m.machine_id is not null and not exists (
   select 1 from asset_costs f where f.machine_id=m.machine_id and f.amount<>0 and f.category='personnel'
    and date_trunc('month',f.occurred_on)=date_trunc('month',m.work_date)
  )
  group by 1,2,3,4,5
 ), personnel_by_job as (
  select project,work_order,usage,sum(hours) personnel_hours,round(sum(amount),2) personnel_cost
  from allocated where machine_id=p_machine group by 1,2,3
 ), personnel_by_machine as (
  select machine_id,sum(hours) personnel_hours,round(sum(amount),2) personnel_cost
  from allocated group by 1
 ), activity as (
  select machine_id,coalesce(max(machine_name),max(article)) name,
   count(*) rows,sum(quantity) filter(where unit='tim') hours,
   case when count(invoiced) filter(where unit='tim')>0
    then coalesce(sum(quantity) filter(where unit='tim' and invoiced is true),0) end billed_hours,
   sum(quantity) filter(where unit in ('bd','dag','dygn')) days,sum(value) value,
   sum(value) filter(where unit='tim')/nullif(sum(quantity) filter(where unit='tim'),0) value_per_hour
  from own group by machine_id
 ), machines as (
  select i.machine_id,n.machine_reference,coalesce(a.name,n.name,i.codes[1]) name,i.codes,
   coalesce(a.rows,0) rows,a.hours,a.billed_hours,a.days,a.value,a.value_per_hour,
   case when a.hours is not null then (select sum(available_hours) from batch_capacity) end available_hours,
   b.booked_cost,b.internal_ao,b.categories,p.personnel_hours,p.personnel_cost,
   case when b.booked_cost is not null or p.personnel_cost is not null
    then coalesce(b.booked_cost,0)+coalesce(p.personnel_cost,0) end total_cost
  from (select machine_id,array_agg(code order by code) codes from identities group by machine_id) i
  left join names n on n.object_id=i.machine_id
  left join activity a using(machine_id)
  left join booked_by_machine b using(machine_id)
  left join personnel_by_machine p using(machine_id)
  where a.machine_id is not null or b.machine_id is not null
 ), usage_totals as (
  select machine_id,usage,count(*) rows,sum(quantity) filter(where unit='tim') hours,sum(value) value
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
   count(*) rows,sum(quantity) filter(where unit='tim') hours,count(distinct (project,work_order)) filter(where nullif(work_order,'') is not null) orders
  from driver_rows group by driver_key
 ), monthly_activity as (
  select to_char(performed_on,'YYYY-MM') month_key,count(*) rows,
   sum(quantity) filter(where unit='tim') hours,
   case when count(invoiced) filter(where unit='tim')>0
    then coalesce(sum(quantity) filter(where unit='tim' and invoiced is true),0) end billed_hours,
   sum(quantity) filter(where unit in ('bd','dag','dygn')) days,sum(value) value,
   sum(value) filter(where unit='tim')/nullif(sum(quantity) filter(where unit='tim'),0) value_per_hour
  from own where machine_id=p_machine and performed_on is not null group by 1
 ), monthly_cost as (
  select month_key,sum(amount) total_cost from (
   select to_char(occurred_on,'YYYY-MM') month_key,amount from scoped_booked
   where machine_id=p_machine and category<>'internal_ao'
   union all
   select to_char(work_date,'YYYY-MM'),amount from allocated where machine_id=p_machine
  ) costs group by 1
 ), months as (
  select month_key,a.rows,a.hours,a.billed_hours,a.days,a.value,a.value_per_hour,c.total_cost,
   case when a.hours is not null then cap.available_hours end available_hours
  from monthly_activity a full join monthly_cost c using(month_key)
  left join batch_capacity cap using(month_key)
 ), jobs_by_usage as (
  select project,work_order,usage,max(project_name) project_name,max(order_name) order_name,
   count(*) rows,sum(quantity) filter(where unit='tim') hours,sum(value) value,array_agg(distinct driver_name order by driver_name) drivers
  from driver_rows group by project,work_order,usage
 ), jobs as (
  select j.*,p.personnel_hours,p.personnel_cost
  from jobs_by_usage j left join personnel_by_job p on p.project=j.project and p.work_order=j.work_order and p.usage=j.usage
 ), other_articles as (
  select category,code,article,unit,count(*) rows,sum(quantity) quantity,sum(value) value
  from source where category<>'Egna maskiner' group by category,code,article,unit
 ), details as (
  select sheet,source_row,performed_on,code,article,unit,quantity,value,driver_name,usage from driver_rows
  where project=p_project and work_order=p_order
 )
 select jsonb_build_object(
  'machines',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('order_count',coalesce(o.order_count,0),'order_refs',coalesce(o.order_refs,array[]::text[]),'usage',coalesce(u.buckets,'{}'::jsonb)) order by m.value desc nulls last,m.name) from machines m left join order_examples o using(machine_id) left join usage_by_machine u using(machine_id)),'[]'::jsonb),
  'cost_accounts',coalesce((select jsonb_agg(to_jsonb(a) order by a.category,a.account,a.source) from booked_accounts a),'[]'::jsonb),
  'drivers',coalesce((select jsonb_agg(to_jsonb(d)-'driver_key' order by d.hours desc nulls last,d.name,d.driver_key) from drivers d),'[]'::jsonb),
  'months',coalesce((select jsonb_agg(to_jsonb(m) order by m.month_key) from months m),'[]'::jsonb),
  'jobs',coalesce((select jsonb_agg(to_jsonb(j) order by j.value desc nulls last,j.project,j.work_order,j.usage) from jobs j),'[]'::jsonb),
  'others',coalesce((select jsonb_agg(to_jsonb(a) order by a.category,a.value desc nulls last,a.code,a.unit) from other_articles a where p_machine is null),'[]'::jsonb),
  'details',coalesce((select jsonb_agg(to_jsonb(d) order by d.performed_on desc nulls last,d.sheet,d.source_row) from details d),'[]'::jsonb)
 ) into report;
 return report;
end $$;
