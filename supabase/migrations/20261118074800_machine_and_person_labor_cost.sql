create or replace function private.hub_next_machine_followup_v2(
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
 ), depreciation_assets as (
  select d.id,d.object_reference,d.source,k.object_id machine_id
  from public.kpi_asset_depreciation_periods d
  join public.hub_identity_keys k on k.tenant_id=t and k.identity_type='asset_depreciation_reference'
   and k.object_type='Project' and k.confidence=1 and k.identity_value=d.object_reference
  where d.tenant_id=t and k.object_id in (select machine_id from asset_projects)
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
   case when r.code in ('PE1002','PE1003') and r.account='7010' and r.unit='tim' then 'Personal'
    when r.code ~* '^IN[0-9]' then 'Inhyrda maskiner och redskap'
    when r.code ~* '^(RE|UT|EL)[0-9]' then 'Redskap och tillbehör'
    when i.machine_id is not null and r.unit in ('tim','bd','dag','dygn') then 'Egna maskiner'
    when r.unit in ('bd','dag','dygn') then 'Dags- och dygnsartiklar'
    else 'Maskinartiklar att koppla' end category
  from jsonb_to_recordset(p_rows) as r(sheet text,source_row integer,project text,project_name text,
   work_order text,order_name text,center text,code text,article text,unit text,performed_on date,
   quantity numeric,value numeric,performed_by text,employee_number text,customer text,invoiced boolean,account text)
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
  where (r.code ~* '^(M|IN|RE|UT|EL)[0-9]' or (r.code in ('PE1002','PE1003') and r.account='7010' and r.unit='tim')) and (p_from is null or r.performed_on>=p_from)
   and (p_to is null or r.performed_on<=p_to)
   and (p_months is null or extract(month from r.performed_on)=any(p_months))
 ), own as materialized (
  select * from source where category='Egna maskiner'
 ), vehicle_cost_facts as materialized (
  select f.vehicle,f.occurred_on,f.amount
  from private.hub_kpi_report_facts_v1 f join active_generation g on g.id=f.generation_id
  where f.tenant_id=t and f.kind='cost' and f.vehicle is not null
   and coalesce(f.category,'other') not in ('personnel','management','overhead')
   and f.source not in ('TransPA','Preliminär arbetskostnad','Overhead')
   and (p_from is null or f.occurred_on>=p_from) and (p_to is null or f.occurred_on<=p_to)
   and (p_months is null or extract(month from f.occurred_on)=any(p_months))
 ), asset_costs as materialized (
  select coalesce(d.machine_id,a.machine_id) machine_id,f.occurred_on,f.amount,f.account,f.source,
   d.object_reference asset_reference,d.source asset_source,
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
  left join asset_projects a on a.project=f.project
  left join depreciation_assets d on f.source='Avskrivningsregister' and d.id::text=f.original->>'register_id'
  where (a.machine_id is not null or d.machine_id is not null) and f.tenant_id=t and f.kind='cost' and f.source not in ('TransPA','Preliminär arbetskostnad','Overhead','Verkstadsschablon')
   and (p_from is null or f.occurred_on>=date_trunc('month',p_from)::date)
   and (p_to is null or f.occurred_on<date_trunc('month',p_to)+interval '1 month')
   and (p_months is null or extract(month from f.occurred_on)=any(p_months))
   -- NeXT posts the same resource time as monthly bookkeeping summaries.
   and not (f.source='NEXT' and coalesce(f.account,'') ~ '^7[0-6][0-9]{2}$'
    and (coalesce(f.original->>'Verifikationstext','') ~* '^arbetstid[[:space:]]+[0-9]{4}-[0-9]{2}'
      or coalesce(f.description,'') ~* '^arbetstid[[:space:]]+[0-9]{4}-[0-9]{2}'))
 ), person_keys as materialized (
  select case when k.identity_type='next_person_name' then 'name' else 'employee' end kind,
   upper(btrim(k.identity_value)) key,(array_agg(distinct k.object_id))[1] person
  from public.hub_identity_keys k join public.hub_objects o on o.tenant_id=t and o.id=k.object_id and o.object_type='Person'
  where k.tenant_id=t and k.object_type='Person' and k.confidence=1
   and k.identity_type in ('next_person_name','next_employee_number')
  group by 1,2 having count(distinct k.object_id)=1
 ), next_workers as materialized (
  select s.*,case when en.person is null or nm.person is null or en.person=nm.person
    then coalesce(en.person,nm.person) end person,
   nullif(upper(btrim(s.employee_number)),'') employee_key,
   nullif(upper(btrim(s.performed_by)),'') name_key
  from source s
  left join person_keys en on en.kind='employee' and en.key=upper(btrim(s.employee_number))
  left join person_keys nm on nm.kind='name' and nm.key=upper(btrim(s.performed_by))
  where s.category in ('Egna maskiner','Personal','Maskinartiklar att koppla','Inhyrda maskiner och redskap')
   and s.unit='tim' and s.quantity is not null and s.performed_on is not null
 ), worker_numbers as (
  select name_key,min(employee_key) employee_key from next_workers
  where name_key is not null and employee_key is not null
  group by name_key having count(distinct employee_key)=1
 ), workers as materialized (
  select w.*,coalesce('person:'||w.person,'next:'||coalesce(w.employee_key,n.employee_key),'name:'||w.name_key) worker
  from next_workers w left join worker_numbers n on n.name_key=w.name_key
 ), machine_days as materialized (
  select distinct project,work_order,performed_on,worker,
   case when category='Egna maskiner' then machine_id end machine_id,usage
  from workers where category<>'Personal' and quantity>0 and project<>'' and work_order<>''
   and (code ~* '^M[0-9]' or article ~* 'gräv|lastare|traktor|dumper|vält')
   and article !~* 'maskinflytt|utan förare'
 ), explicit_labor as materialized (
  select w.*,a.machine_id assigned_machine,a.usage machine_usage,
   case w.code when 'PE1002' then 'operator' else 'groundworker' end labor_role
  from workers w
  left join lateral (
   select (array_agg(d.machine_id))[1] machine_id,min(d.usage) usage
   from machine_days d where (d.project,d.work_order,d.performed_on)=(w.project,w.work_order,w.performed_on)
    and (d.worker=w.worker or not exists (
     select 1 from machine_days known where (known.project,known.work_order,known.performed_on)=(w.project,w.work_order,w.performed_on)
      and known.worker=w.worker
    ))
   having count(distinct d.machine_id)=1 and count(*)=count(d.machine_id) and count(distinct d.usage)=1
  ) a on true
  where w.category='Personal'
 ), labor_rows as (
  select e.person,e.worker,e.performed_on work_date,e.project,e.work_order,e.machine_usage usage,e.assigned_machine machine_id,e.labor_role,
   e.quantity hours,e.value,e.performed_by
  from explicit_labor e
  union all
  select w.person,w.worker,w.performed_on,w.project,w.work_order,w.usage,w.machine_id,'operator',w.quantity,null::numeric,w.performed_by
  from workers w
  where w.category='Egna maskiner' and w.worker is not null and w.article !~* 'maskinflytt|utan förare'
   and not exists (
    select 1 from explicit_labor e where e.assigned_machine=w.machine_id and e.worker=w.worker
     and (e.project,e.work_order,e.performed_on)=(w.project,w.work_order,w.performed_on)
   )
 ), labor_rates(role,rate,source) as (
  -- Fortnox can replace this cost basis using the canonical person and work date in labor_rows.
  values ('operator',390::numeric,'Schablon'),('groundworker',400::numeric,'Schablon')
 ), allocated as materialized (
  select l.*,l.hours*r.rate amount
  from labor_rows l join labor_rates r on r.role=l.labor_role
  where l.hours<>0
 ), scoped_booked as materialized (
  select b.* from asset_costs b
  where (p_from is null or b.occurred_on>=p_from) and (p_to is null or b.occurred_on<=p_to)
   and not (b.category='personnel' and exists (
    select 1 from allocated a where a.machine_id=b.machine_id and date_trunc('month',a.work_date)=date_trunc('month',b.occurred_on)
   ))
 ), booked as (
  select machine_id,category,sum(amount) amount
  from scoped_booked group by 1,2
 ), booked_by_machine as (
  select machine_id,sum(amount) filter(where category<>'internal_ao') booked_cost,
   sum(amount) filter(where category='internal_ao') internal_ao,
   jsonb_object_agg(category,amount) filter(where category<>'internal_ao') categories
  from booked group by machine_id
 ), booked_accounts as (
  select category,account,source,asset_reference,asset_source,sum(amount) amount,count(*) row_count
  from scoped_booked where machine_id=p_machine group by 1,2,3,4,5
 ), personnel_by_job as (
  select project,work_order,usage,sum(hours) personnel_hours,round(sum(amount),2) personnel_cost
  from allocated where machine_id=p_machine group by 1,2,3
 ), personnel_by_machine as (
  select machine_id,sum(hours) personnel_hours,round(sum(amount),2) personnel_cost,
   sum(hours) filter(where labor_role='operator') operator_hours,
   round(sum(amount) filter(where labor_role='operator'),2) operator_cost,
   sum(hours) filter(where labor_role='groundworker') groundworker_hours,
   round(sum(amount) filter(where labor_role='groundworker'),2) groundworker_cost
  from allocated where machine_id is not null group by 1
 ), independent as (
  select a.worker,a.person,max(nullif(btrim(a.performed_by),'')) name,
   sum(a.hours) hours,round(sum(a.amount),2) personnel_cost,round(sum(a.value),2) value,
   sum(a.hours) filter(where a.labor_role='operator') operator_hours,
   sum(a.hours) filter(where a.labor_role='groundworker') groundworker_hours
  from allocated a
  where a.machine_id is null group by 1,2
 ), vehicle_links as materialized (
  select rel.from_object_id person,rel.to_object_id vehicle,rel.valid_from,rel.valid_to,k.registration
  from public.hub_object_relations rel
  join lateral (
   select min(upper(btrim(identity_value))) registration
   from public.hub_identity_keys k where k.tenant_id=t and k.object_id=rel.to_object_id
    and k.object_type='Vehicle' and k.identity_type='registration_number' and k.confidence=1
   having count(distinct upper(btrim(identity_value)))=1
  ) k on true
  where rel.tenant_id=t and rel.relation_type='person_work_vehicle' and rel.status='active' and rel.confidence=1
   and (p_from is null or rel.valid_to is null or rel.valid_to>=p_from)
   and (p_to is null or rel.valid_from is null or rel.valid_from<=p_to)
   and exists(select 1 from independent i where i.person=rel.from_object_id)
 ), vehicle_costs as (
  select v.person,round(sum(f.amount),2) vehicle_cost
  from vehicle_cost_facts f join vehicle_links v on v.registration=f.vehicle
   and (v.valid_from is null or v.valid_from<=f.occurred_on)
   and (v.valid_to is null or v.valid_to>=f.occurred_on)
  group by v.person
 ), person_units as (
  select i.*, coalesce((
   select array_agg(distinct v.registration order by v.registration) from vehicle_links v where v.person=i.person
  ),array[]::text[]) vehicles,c.vehicle_cost,i.personnel_cost+coalesce(c.vehicle_cost,0) total_cost
  from independent i left join vehicle_costs c using(person)
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
   p.operator_hours,p.operator_cost,p.groundworker_hours,p.groundworker_cost,
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
  from source where category not in ('Egna maskiner','Personal') group by category,code,article,unit
 ), details as (
  select sheet,source_row,performed_on,code,article,unit,quantity,value,driver_name,usage from driver_rows
  where project=p_project and work_order=p_order
 )
 select jsonb_build_object(
  'machines',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('order_count',coalesce(o.order_count,0),'order_refs',coalesce(o.order_refs,array[]::text[]),'usage',coalesce(u.buckets,'{}'::jsonb)) order by m.value desc nulls last,m.name) from machines m left join order_examples o using(machine_id) left join usage_by_machine u using(machine_id)),'[]'::jsonb),
  'labor_rates',(select jsonb_object_agg(role,jsonb_build_object('rate',rate,'source',source)) from labor_rates),
  'person_units',coalesce((select jsonb_agg(to_jsonb(i)-'worker' order by i.name,i.person) from person_units i where p_machine is null),'[]'::jsonb),
  'cost_accounts',coalesce((select jsonb_agg(to_jsonb(a) order by a.category,a.account,a.source) from booked_accounts a),'[]'::jsonb),
  'drivers',coalesce((select jsonb_agg(to_jsonb(d)-'driver_key' order by d.hours desc nulls last,d.name,d.driver_key) from drivers d),'[]'::jsonb),
  'months',coalesce((select jsonb_agg(to_jsonb(m) order by m.month_key) from months m),'[]'::jsonb),
  'jobs',coalesce((select jsonb_agg(to_jsonb(j) order by j.value desc nulls last,j.project,j.work_order,j.usage) from jobs j),'[]'::jsonb),
  'others',coalesce((select jsonb_agg(to_jsonb(a) order by a.category,a.value desc nulls last,a.code,a.unit) from other_articles a where p_machine is null),'[]'::jsonb),
  'details',coalesce((select jsonb_agg(to_jsonb(d) order by d.performed_on desc nulls last,d.sheet,d.source_row) from details d),'[]'::jsonb)
 ) into report;
 return report;
end $$;

revoke all on function private.hub_next_machine_followup_v2(uuid,uuid,jsonb,date,date,uuid,text,text,integer[]) from public,anon,authenticated;
grant execute on function private.hub_next_machine_followup_v2(uuid,uuid,jsonb,date,date,uuid,text,text,integer[]) to authenticated;

create or replace function public.hub_next_machine_followup_v2(
 t uuid,p_batch uuid,p_rows jsonb,p_from date,p_to date,p_machine uuid,p_project text,p_order text,p_months integer[]
)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.hub_next_machine_followup_v2(t,p_batch,p_rows,p_from,p_to,p_machine,p_project,p_order,p_months)
$$;
revoke all on function public.hub_next_machine_followup_v2(uuid,uuid,jsonb,date,date,uuid,text,text,integer[]) from public,anon,authenticated;
grant execute on function public.hub_next_machine_followup_v2(uuid,uuid,jsonb,date,date,uuid,text,text,integer[]) to authenticated;

create or replace function private.hub_set_person_work_vehicle(t uuid,p_person uuid,p_registration text,p_from date)
returns void language plpgsql security definer set search_path='' as $$
declare
 registration text:=upper(regexp_replace(btrim(p_registration),'[[:space:]-]','','g'));
 vehicle uuid;
 previous public.hub_object_relations%rowtype;
begin
 if auth.uid() is null or public.hub_has_permission(t,'kpi.manage') is not true then
  raise exception 'Access denied' using errcode='42501';
 end if;
 if p_from is null or not exists(select 1 from public.hub_objects o where o.tenant_id=t and o.id=p_person and o.object_type='Person') then
  raise exception 'Invalid person or date' using errcode='22023';
 end if;
 select (array_agg(distinct k.object_id))[1] into vehicle
 from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=t and o.object_type='Vehicle'
 where k.tenant_id=t and k.object_type='Vehicle' and k.identity_type='registration_number'
  and k.confidence=1 and upper(btrim(k.identity_value))=registration
 having count(distinct k.object_id)=1;
 if vehicle is null then
  raise exception 'Vehicle not found' using errcode='P0002';
 end if;

 -- Serialize period changes so that every vehicle has at most one person on a given day.
 perform pg_advisory_xact_lock(hashtextextended('person_work_vehicle:'||t::text,0));
 select * into previous from public.hub_object_relations r
 where r.tenant_id=t and r.relation_type='person_work_vehicle' and r.status='active'
  and r.from_object_id=p_person and r.valid_to is null;
 if found and previous.to_object_id=vehicle and previous.valid_from<=p_from then
  return;
 end if;
 if exists(select 1 from public.hub_object_relations r
  where r.tenant_id=t and r.relation_type='person_work_vehicle' and r.status='active'
   and (r.valid_to is null or r.valid_to>=p_from)
   and (r.to_object_id=vehicle or
    (r.from_object_id=p_person and
     (r.id is distinct from previous.id or r.valid_from is null or r.valid_from>=p_from))))
 then
  raise exception 'Vehicle or person already assigned in period' using errcode='23P01';
 end if;
 if previous.id is not null then
  update public.hub_object_relations set valid_to=p_from-1,updated_at=now() where id=previous.id;
 end if;
 insert into public.hub_object_relations(tenant_id,from_object_id,to_object_id,relation_type,valid_from,evidence)
 values(t,p_person,vehicle,'person_work_vehicle',p_from,jsonb_build_object('user_id',auth.uid(),'source','Manual KPI assignment'));
end $$;

create or replace function public.hub_set_person_work_vehicle(t uuid,p_person uuid,p_registration text,p_from date)
returns void language sql security invoker set search_path='' as $$
 select private.hub_set_person_work_vehicle(t,p_person,p_registration,p_from)
$$;
revoke all on function private.hub_set_person_work_vehicle(uuid,uuid,text,date) from public,anon,authenticated;
revoke all on function public.hub_set_person_work_vehicle(uuid,uuid,text,date) from public,anon,authenticated;
grant execute on function private.hub_set_person_work_vehicle(uuid,uuid,text,date) to authenticated;
grant execute on function public.hub_set_person_work_vehicle(uuid,uuid,text,date) to authenticated;
