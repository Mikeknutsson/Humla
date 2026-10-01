create table public.kpi_unit_periods (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.hub_tenants(id),unit_id uuid not null references public.kpi_units(id),
 valid_from date not null,valid_to date,payload jsonb not null,created_by uuid references auth.users(id),created_at timestamptz not null default now(),
 check(valid_to is null or valid_to>=valid_from),unique(unit_id,valid_from)
);
alter table public.kpi_unit_periods enable row level security;
create policy kpi_unit_periods_read on public.kpi_unit_periods for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.read'));
grant select on public.kpi_unit_periods to authenticated;
create function private.hub_kpi_units_at_date_v1(p_tenant_id uuid,p_date date) returns setof public.kpi_units
language sql stable security definer set search_path='' as $$
 select (jsonb_populate_record(null::public.kpi_units,to_jsonb(u)||coalesce(v.payload,'{}')||case when v.id is not null then jsonb_build_object('valid_from',v.valid_from,'valid_to',v.valid_to) else '{}' end)).*
 from public.kpi_units u left join public.kpi_unit_periods v on v.unit_id=u.id and v.tenant_id=u.tenant_id and v.valid_from<=p_date and (v.valid_to is null or v.valid_to>=p_date)
 where u.tenant_id=p_tenant_id and u.origin in ('manual','manual_builder') and auth.uid() is not null and public.hub_has_permission(p_tenant_id,'kpi.read')
 and (v.id is not null or (not exists(select 1 from public.kpi_unit_periods x where x.unit_id=u.id) and u.valid_from<=p_date and (u.valid_to is null or u.valid_to>=p_date)))
$$;
revoke all on function private.hub_kpi_units_at_date_v1(uuid,date) from public,anon;
grant execute on function private.hub_kpi_units_at_date_v1(uuid,date) to authenticated;
create function public.hub_kpi_save_unit_v2(p_tenant_id uuid,p_payload jsonb,p_unit_id uuid default null,p_revision integer default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid; old public.kpi_units; effective date; ending date; latest date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI administrator required'; end if;
 effective:=(p_payload->>'valid_from')::date;ending:=nullif(p_payload->>'valid_to','')::date;
 if effective is null or (ending is not null and ending<effective) or length(trim(p_payload->>'name')) not between 1 and 120 or p_payload->>'unit_type' not in ('vehicle','person','overhead','compound') then raise exception 'Invalid unit';end if;
 if jsonb_array_length(p_payload->'projects')+jsonb_array_length(p_payload->'registrations')+jsonb_array_length(p_payload->'employees') not between 1 and 300 then raise exception 'Select 1-300 references';end if;
 if exists(select 1 from jsonb_array_elements_text(p_payload->'registrations') r where r !~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$') then raise exception 'Invalid registration';end if;
 if p_unit_id is null then
  insert into public.kpi_units(tenant_id,name,unit_type,projects,registrations,employees,valid_from,valid_to,enabled,origin)
  values(p_tenant_id,trim(p_payload->>'name'),p_payload->>'unit_type',array(select jsonb_array_elements_text(p_payload->'projects')),array(select jsonb_array_elements_text(p_payload->'registrations')),array(select jsonb_array_elements_text(p_payload->'employees')),effective,ending,coalesce((p_payload->>'enabled')::boolean,true),'manual') returning id into uid;
 else
  select * into old from public.kpi_units where id=p_unit_id and tenant_id=p_tenant_id for update;
  if not found or old.revision<>p_revision then raise exception 'Unit changed; reload before saving';end if;
  select max(valid_from) into latest from public.kpi_unit_periods where unit_id=old.id;
  if effective<=coalesce(latest,old.valid_from) then raise exception 'New composition must start after the latest period; history cannot be overwritten';end if;
  if latest is null then insert into public.kpi_unit_periods(tenant_id,unit_id,valid_from,valid_to,payload,created_by) values(p_tenant_id,old.id,old.valid_from,least(effective-1,coalesce(old.valid_to,effective-1)),to_jsonb(old),auth.uid());
  else update public.kpi_unit_periods set valid_to=effective-1 where unit_id=old.id and valid_from=latest and (valid_to is null or valid_to>=effective);end if;
  uid:=old.id;
  -- Current register fields are a display cache; historical queries use periods.
  update public.kpi_units set name=trim(p_payload->>'name'),unit_type=p_payload->>'unit_type',projects=array(select jsonb_array_elements_text(p_payload->'projects')),registrations=array(select jsonb_array_elements_text(p_payload->'registrations')),employees=array(select jsonb_array_elements_text(p_payload->'employees')),enabled=coalesce((p_payload->>'enabled')::boolean,true) where id=uid;
 end if;
 insert into public.kpi_unit_periods(tenant_id,unit_id,valid_from,valid_to,payload,created_by) values(p_tenant_id,uid,effective,ending,p_payload,auth.uid());
 return uid;
end $$;
revoke all on function public.hub_kpi_save_unit_v2(uuid,jsonb,uuid,integer) from public,anon;
grant execute on function public.hub_kpi_save_unit_v2(uuid,jsonb,uuid,integer) to authenticated;

create or replace function private.hub_kpi_financial_facts_v1(p_tenant_id uuid,p_from date,p_to date)
returns table(fact_id text,occurred_on date,kind text,amount numeric,category text,project text,vehicle text,unit_id uuid,unit_name text,business_group text,source text,description text,account text,file_name text,row_number integer,original jsonb)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 then raise exception 'Invalid period'; end if;
 return query
 with cfg0 as (
  select coalesce(monthly_salary,34000)::numeric salary,coalesce(weekly_hours,40)::numeric wh,coalesce(overtime_multiplier,1.5)::numeric ot,
   (1+(coalesce(employer_contribution_pct,31.42)+coalesce(pension_pct,4.5)+coalesce(other_overhead_pct,0))/100)::numeric load
  from public.kpi_personnel_salary_settings where tenant_id=p_tenant_id and is_default limit 1
 ), cfg as (select * from cfg0 union all select 34000,40,1.5,1.3592 where not exists(select 1 from cfg0)),
 times as (select t.*,date_trunc('week',work_date)::date wk from public.kpi_transpa_time_facts t where t.tenant_id=p_tenant_id and work_date between p_from and p_to and work_hours>0),
 weeks as (select employee_id,wk,sum(work_hours) hours from times group by 1,2),
 payroll as (
  select t.*,(case when w.hours<=c.wh then t.work_hours else t.work_hours*c.wh/w.hours end +
   case when w.hours<=c.wh then 0 else t.work_hours*(w.hours-c.wh)/w.hours*c.ot end)*c.salary/(c.wh*52/12)*c.load pc
  from times t join weeks w using(employee_id,wk) cross join cfg c
 ), imports as (
  select x.id::text fid,x.occurred_on dt,x.data_kind k,x.amount amt,
   case when x.data_kind='revenue' then coalesce(ar.revenue_category,'unclassified')
    when x.project_reference='9009' then 'hired' when x.project_reference='5100' then 'tipp_deponi'
    when x.account in ('5360','5621','5631') then 'fuel' else coalesce(cr.cost_category,'other') end cat,
   case when x.data_kind='revenue' then case when ar.target_type='project' then nullif(trim(ar.project_reference),'') else null end
    else coalesce(nullif(x.allocation->>'allocation_reference',''),x.project_reference) end proj,
   case when x.data_kind='revenue' and ar.target_type='vehicle' then upper(trim(x.vehicle_registration))
    when x.data_kind='cost' then null else null end reg,
   case when x.data_kind='cost' then 'NEXT' else 'Workify' end src,x.description descr,x.account acc,b.file_name fn,x.row_number rn,x.source_data raw
  from public.kpi_import_rows x join public.kpi_import_batches b on b.id=x.batch_id
  left join lateral (select a.* from public.kpi_workify_article_rules a where a.tenant_id=p_tenant_id and a.enabled and a.article_number=coalesce(x.source_data->>'Artikelnummer','') and x.occurred_on>=a.valid_from and (a.valid_to is null or x.occurred_on<=a.valid_to) order by a.valid_from desc,a.id limit 1) ar on true
  left join lateral (select r.cost_category from public.kpi_cost_category_rules r where r.tenant_id=p_tenant_id and r.account=x.account and x.occurred_on>=r.valid_from and (r.valid_to is null or x.occurred_on<=r.valid_to) order by r.valid_from desc,r.id limit 1) cr on true
  where x.tenant_id=p_tenant_id and x.is_valid and x.data_kind in ('revenue','cost') and x.occurred_on between p_from and p_to
 ), raw_facts as (
  select * from imports
  union all
  select 'transpa:'||t.time_report_id||':'||coalesce(j.ordinality,0),t.work_date,'cost',t.pc/greatest(jsonb_array_length(coalesce(t.transpa_vehicle_ids,'[]')),1),
   'personnel',null,upper(trim(v.payload->>'registrationNumber')),'TransPA',
   'Beräknad personalkostnad från TransPA-tid (Hub-schablon)',null,null,null,
   jsonb_build_object('time_report_id',t.time_report_id,'employee_id',t.employee_id,'work_date',t.work_date,'work_hours',t.work_hours,'report_status',t.report_status,'calculation','hub_kpi_personnel_costs_engine_v1','actual_payroll',false)
  from payroll t left join lateral jsonb_array_elements(t.transpa_vehicle_ids) with ordinality j(value,ordinality) on true
  left join public.hub_transpa_entities v on v.tenant_id=p_tenant_id and v.entity_type='vehicle' and v.external_id=j.value#>>'{}'
  union all
  select 'depreciation:'||d.id||':'||gs::date,greatest(gs::date,p_from,d.valid_from),'cost',d.monthly_depreciation,'depreciation',null,upper(trim(d.object_reference)),'Avskrivningsregister',
   'Månadsavskrivning',null,null,null,jsonb_build_object('register_id',d.id,'valid_from',d.valid_from,'valid_to',d.valid_to,'monthly_depreciation',d.monthly_depreciation)
  from public.kpi_asset_depreciation_periods d cross join lateral generate_series(date_trunc('month',greatest(p_from,d.valid_from)),date_trunc('month',least(p_to,coalesce(d.valid_to,p_to))),interval '1 month') gs
  where d.tenant_id=p_tenant_id and d.valid_from<=p_to and (d.valid_to is null or d.valid_to>=p_from)
 ), mapped as (
  select f.*,case when f.proj='9009' or f.reg='LASTBIL' then 'LASTBIL' else coalesce(nullif(f.reg,''),m.reg) end vrn
  from raw_facts f left join lateral (
   select case when count(distinct upper(trim(vehicle_registration)))=1 then max(upper(trim(vehicle_registration))) end reg
   from public.kpi_project_unit_mappings pm where pm.tenant_id=p_tenant_id and pm.enabled and pm.project_reference=f.proj and f.dt>=coalesce(pm.valid_from,'2000-01-01') and (pm.valid_to is null or f.dt<=pm.valid_to)
  ) m on true
 ), related as (
  select f.*,u.uid,u.uname,
   case when f.proj='9009' or f.vrn='LASTBIL' then 'Inhyrda' else coalesce(bg.name,'Ej klassificerat') end grp
  from mapped f left join lateral (
   select case when count(distinct un.id)=1 then (array_agg(distinct un.id))[1] end uid,
    case when count(distinct un.id)=1 then max(un.name) end uname
   from private.hub_kpi_units_at_date_v1(p_tenant_id,f.dt) un where un.tenant_id=p_tenant_id and un.enabled and un.origin in ('manual','manual_builder') and un.valid_from<=f.dt and (un.valid_to is null or un.valid_to>=f.dt)
   and (f.proj=any(un.projects) or f.vrn=any(un.registrations) or f.raw->>'employee_id'=any(un.employees) or exists(
    select 1 from public.kpi_unit_components c where c.tenant_id=p_tenant_id and c.unit_id=un.id and c.component_type in ('vehicle','trailer','other') and upper(trim(c.component_reference))=f.vrn and coalesce(c.valid_from,un.valid_from)<=f.dt and (c.valid_to is null or f.dt<=c.valid_to)))
  ) u on true
  left join lateral (
   select case when count(distinct p.business_group_id)=1 then (array_agg(distinct p.business_group_id))[1] end gid
   from public.kpi_project_business_groups p where p.tenant_id=p_tenant_id and p.project_reference=f.proj and f.dt>=coalesce(p.valid_from,'2000-01-01') and (p.valid_to is null or f.dt<=p.valid_to)
  ) pg on true left join public.kpi_business_groups bg on bg.id=pg.gid and bg.tenant_id=p_tenant_id and bg.enabled
 ) select f.fid,f.dt,f.k,f.amt,f.cat,f.proj,f.vrn,f.uid,f.uname,f.grp,f.src,f.descr,f.acc,f.fn,f.rn,f.raw from related f;
end $$;
revoke all on function private.hub_kpi_financial_facts_v1(uuid,date,date) from public,anon;
grant execute on function private.hub_kpi_financial_facts_v1(uuid,date,date) to authenticated;

create or replace function public.hub_kpi_analysis_v1(p_tenant_id uuid,p_from date,p_to date,p_filters jsonb default '{}',p_level text default 'group',p_grain text default 'month',p_page integer default 0,p_export boolean default false)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if p_level not in ('group','unit','project','transaction') or p_grain not in ('year','month','week','day') or p_page<0 then raise exception 'Invalid analysis filter';end if;
 with facts as materialized(select * from private.hub_kpi_financial_facts_v1(p_tenant_id,p_from,p_to)), scoped as (
  select f.* from facts f where
   (not(p_filters?'group') or f.business_group=p_filters->>'group') and
   (not(p_filters?'unit') or coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=p_filters->>'unit') and
   (not(p_filters?'vehicle') or f.vehicle=p_filters->>'vehicle') and
   (not(p_filters?'project') or coalesce(f.project,'unassigned')=p_filters->>'project') and
   (not(p_filters?'category') or f.category=p_filters->>'category') and
   (not(p_filters?'kind') or f.kind=p_filters->>'kind') and
   (not(p_filters?'source') or f.source=p_filters->>'source') and
   (not(p_filters?'date_from') or f.occurred_on>=(p_filters->>'date_from')::date) and
   (not(p_filters?'date_to') or f.occurred_on<=(p_filters->>'date_to')::date)
 ), summary as (
  select round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,
   round(coalesce(sum(amount) filter(where source='NEXT'),0),2) next_cost,round(coalesce(sum(amount) filter(where source='TransPA'),0),2) personnel_cost,count(*) rows from scoped
 ), keyed as (
  select *,case p_level when 'group' then business_group when 'unit' then coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') when 'project' then coalesce(project,'unassigned') else fact_id end group_key,
   case p_level when 'group' then business_group when 'unit' then coalesce(unit_name,vehicle,'Ej fördelat') when 'project' then coalesce(project,'Ej projektfördelat') else coalesce(description,fact_id) end group_label
  from scoped
 ), groups as (
  select group_key key,max(group_label) label,count(*) rows,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,
   round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,
   round(coalesce(sum(case when kind='revenue' then amount else -amount end),0),2) result from keyed group by group_key
 ), periods as (
  select case p_grain when 'year' then make_date(extract(year from occurred_on)::int-case when extract(month from occurred_on)<9 then 1 else 0 end,9,1) else date_trunc(p_grain,occurred_on)::date end period_start,
   round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,
   round(coalesce(sum(case when kind='revenue' then amount else -amount end),0),2) result,count(*) rows from scoped group by 1
 ), page_rows as (select * from scoped order by occurred_on desc,fact_id limit case when p_export then 50001 else 100 end offset case when p_export then 0 else p_page*100 end)
 select jsonb_build_object('period',jsonb_build_object('from',p_from,'to',p_to),'filters',p_filters,'level',p_level,'grain',p_grain,'page',p_page,
  'summary',(select to_jsonb(s)||jsonb_build_object('result',revenue-cost,'margin_pct',case when revenue<>0 then round((revenue-cost)/revenue*100,2) else null end) from summary s),
  'groups',coalesce((select jsonb_agg(to_jsonb(g) order by g.label) from groups g),'[]'),
  'periods',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('period_end',least(p_to,coalesce((p_filters->>'date_to')::date,p_to),case p_grain when 'year' then (period_start+interval '1 year'-interval '1 day')::date when 'month' then (period_start+interval '1 month'-interval '1 day')::date when 'week' then period_start+6 else period_start end),'period_start',greatest(p_from,coalesce((p_filters->>'date_from')::date,p_from),period_start)) order by period_start) from periods p),'[]'),
  'transactions',coalesce((select jsonb_agg(to_jsonb(r)) from page_rows r),'[]'),
  'page_size',100,'export_limit_exceeded',(select count(*)>50000 from scoped)
 ) into result;
 return result;
end $$;
revoke all on function public.hub_kpi_analysis_v1(uuid,date,date,jsonb,text,text,integer,boolean) from public,anon;
grant execute on function public.hub_kpi_analysis_v1(uuid,date,date,jsonb,text,text,integer,boolean) to authenticated;

