alter table public.kpi_cost_category_rules add column if not exists include_in_vehicle_result boolean;
create table public.kpi_project_vehicle_periods (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.hub_tenants(id),project_reference text not null,vehicle_registration text not null,
 valid_from date not null,valid_to date,created_by uuid references auth.users(id),created_at timestamptz not null default now(),check(valid_to is null or valid_to>=valid_from),unique(tenant_id,project_reference,valid_from)
);
alter table public.kpi_project_vehicle_periods enable row level security;
create policy kpi_project_vehicle_periods_read on public.kpi_project_vehicle_periods for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.read'));
grant select on public.kpi_project_vehicle_periods to authenticated;
create function public.hub_kpi_admin_rules_v1(p_tenant_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI administrator required';end if;
 return jsonb_build_object('groups',(select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order),'[]') from public.kpi_business_groups x where tenant_id=p_tenant_id and enabled),
 'cost',(select coalesce(jsonb_agg(to_jsonb(x) order by x.account,x.valid_from),'[]') from public.kpi_cost_category_rules x where tenant_id=p_tenant_id),
 'article',(select coalesce(jsonb_agg(to_jsonb(x) order by x.article_number,x.valid_from),'[]') from public.kpi_workify_article_rules x where tenant_id=p_tenant_id),
 'project_group',(select coalesce(jsonb_agg(to_jsonb(x) order by x.project_reference,x.valid_from),'[]') from public.kpi_project_business_groups x where tenant_id=p_tenant_id),
 'project_vehicle',(select coalesce(jsonb_agg(to_jsonb(x) order by x.project_reference,x.valid_from),'[]') from public.kpi_project_vehicle_periods x where tenant_id=p_tenant_id),
 'depreciation',(select coalesce(jsonb_agg(to_jsonb(x) order by x.object_reference,x.valid_from),'[]') from public.kpi_asset_depreciation_periods x where tenant_id=p_tenant_id));
end $$;
revoke all on function public.hub_kpi_admin_rules_v1(uuid) from public,anon;
grant execute on function public.hub_kpi_admin_rules_v1(uuid) to authenticated;
create function public.hub_kpi_save_rule_v1(p_tenant_id uuid,p_kind text,p_rule jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare effective date; ending date; reference text; cat text; result uuid; reg text;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI administrator required';end if;
 effective:=(p_rule->>'valid_from')::date;ending:=nullif(p_rule->>'valid_to','')::date;reference:=trim(p_rule->>'reference');cat:=p_rule->>'category';reg:=upper(trim(p_rule->>'vehicle'));
 if effective is null or nullif(reference,'') is null or length(reference)>100 or (ending is not null and ending<effective) then raise exception 'Invalid reference/date';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||p_kind||reference,0));
 if p_kind='project_group' then return public.hub_kpi_set_project_group_v2(p_tenant_id,reference,(p_rule->>'group_id')::uuid,effective);
 elsif p_kind='cost' then
  if reference !~ '^[0-9]{1,8}$' or cat not in ('personnel','fuel','service_repair','depreciation','fixed','other','material','tipp_deponi','hired') then raise exception 'Invalid account/category';end if;
  if exists(select 1 from public.kpi_cost_category_rules where tenant_id=p_tenant_id and account=reference and valid_from>=effective) then raise exception 'Start date must follow existing history';end if;
  update public.kpi_cost_category_rules set valid_to=effective-1 where tenant_id=p_tenant_id and account=reference and (valid_to is null or valid_to>=effective);
  insert into public.kpi_cost_category_rules(tenant_id,account,cost_category,valid_from,valid_to,source,include_in_vehicle_result) values(p_tenant_id,reference,cat,effective,ending,'kpi_admin_dated',coalesce((p_rule->>'include_in_vehicle_result')::boolean,true)) returning id into result;
 elsif p_kind='article' then
  if p_rule->>'target_type' not in ('vehicle','project') or cat not in ('transport','material','tipp','tipp_deponi','hired','other') or (p_rule->>'target_type'='project' and nullif(trim(p_rule->>'project'),'') is null) then raise exception 'Invalid article allocation';end if;
  if exists(select 1 from public.kpi_workify_article_rules where tenant_id=p_tenant_id and article_number=reference and valid_from>=effective) then raise exception 'Start date must follow existing history';end if;
  update public.kpi_workify_article_rules set valid_to=effective-1 where tenant_id=p_tenant_id and article_number=reference and (valid_to is null or valid_to>=effective);
  insert into public.kpi_workify_article_rules(tenant_id,article_number,project_reference,article_name,target_type,revenue_category,valid_from,valid_to,enabled,source_hash) values(p_tenant_id,reference,case when p_rule->>'target_type'='project' then trim(p_rule->>'project') end,p_rule->>'name',p_rule->>'target_type',cat,effective,ending,true,md5(p_rule::text)) returning id into result;
 elsif p_kind='project_vehicle' then
  if reg !~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then raise exception 'Invalid registration';end if;
  if exists(select 1 from public.kpi_project_vehicle_periods where tenant_id=p_tenant_id and project_reference=reference and valid_from>=effective) then raise exception 'Start date must follow existing history';end if;
  if not exists(select 1 from public.kpi_project_vehicle_periods where tenant_id=p_tenant_id and project_reference=reference) then
   insert into public.kpi_project_vehicle_periods(tenant_id,project_reference,vehicle_registration,valid_from,valid_to,created_by)
   select p_tenant_id,reference,vehicle_registration,coalesce(valid_from,'2000-01-01'),least(coalesce(valid_to,effective-1),effective-1),auth.uid() from public.kpi_project_unit_mappings where tenant_id=p_tenant_id and project_reference=reference and enabled and coalesce(valid_from,'2000-01-01')<effective;
  end if;
  update public.kpi_project_vehicle_periods set valid_to=effective-1 where tenant_id=p_tenant_id and project_reference=reference and (valid_to is null or valid_to>=effective);
  insert into public.kpi_project_vehicle_periods(tenant_id,project_reference,vehicle_registration,valid_from,valid_to,created_by) values(p_tenant_id,reference,reg,effective,ending,auth.uid()) returning id into result;
 elsif p_kind='depreciation' then
  if (p_rule->>'monthly_amount')::numeric<0 or (p_rule->>'monthly_amount')::numeric>10000000 then raise exception 'Invalid monthly amount';end if;
  if exists(select 1 from public.kpi_asset_depreciation_periods where tenant_id=p_tenant_id and object_reference=reference and valid_from>=effective) then raise exception 'Start date must follow existing history';end if;
  update public.kpi_asset_depreciation_periods set valid_to=effective-1 where tenant_id=p_tenant_id and object_reference=reference and (valid_to is null or valid_to>=effective);
  insert into public.kpi_asset_depreciation_periods(tenant_id,object_reference,monthly_depreciation,valid_from,valid_to,source) values(p_tenant_id,reference,(p_rule->>'monthly_amount')::numeric,effective,ending,'kpi_admin_dated') returning id into result;
 else raise exception 'Unknown rule type';end if;
 return result;
end $$;
revoke all on function public.hub_kpi_save_rule_v1(uuid,text,jsonb) from public,anon;
grant execute on function public.hub_kpi_save_rule_v1(uuid,text,jsonb) to authenticated;

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
   case when x.data_kind='cost' then 'NEXT' else 'Workify' end src,x.description descr,x.account acc,b.file_name fn,x.row_number rn,case when x.data_kind='cost' then x.source_data||jsonb_build_object('_humla_include_in_vehicle_result',cr.include_in_vehicle_result) else x.source_data end raw
  from public.kpi_import_rows x join public.kpi_import_batches b on b.id=x.batch_id
  left join lateral (select a.* from public.kpi_workify_article_rules a where a.tenant_id=p_tenant_id and a.enabled and a.article_number=coalesce(x.source_data->>'Artikelnummer','') and x.occurred_on>=a.valid_from and (a.valid_to is null or x.occurred_on<=a.valid_to) order by a.valid_from desc,a.id limit 1) ar on true
  left join lateral (select r.cost_category,r.include_in_vehicle_result from public.kpi_cost_category_rules r where r.tenant_id=p_tenant_id and r.account=x.account and x.occurred_on>=r.valid_from and (r.valid_to is null or x.occurred_on<=r.valid_to) order by r.valid_from desc,r.id limit 1) cr on true
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
  select f.*,case when f.k='cost' and f.raw->>'_humla_include_in_vehicle_result'='false' then null when f.proj='9009' or f.reg='LASTBIL' then 'LASTBIL' else coalesce(nullif(f.reg,''),m.reg) end vrn
  from raw_facts f left join lateral (
   select case when count(distinct upper(trim(vehicle_registration)))=1 then max(upper(trim(vehicle_registration))) end reg
   from (select project_reference,vehicle_registration,valid_from,valid_to,true enabled,tenant_id from public.kpi_project_vehicle_periods where tenant_id=p_tenant_id union all select project_reference,vehicle_registration,valid_from,valid_to,enabled,tenant_id from public.kpi_project_unit_mappings legacy where tenant_id=p_tenant_id and not exists(select 1 from public.kpi_project_vehicle_periods h where h.tenant_id=p_tenant_id and h.project_reference=legacy.project_reference)) pm where pm.tenant_id=p_tenant_id and pm.enabled and pm.project_reference=f.proj and f.dt>=coalesce(pm.valid_from,'2000-01-01') and (pm.valid_to is null or f.dt<=pm.valid_to)
  ) m on true
 ), related as (
  select f.*,u.uid,u.uname,
   case when f.proj='9009' or f.vrn='LASTBIL' then 'Inhyrda' else coalesce(bg.name,'Ej klassificerat') end grp
  from mapped f left join lateral (
   select case when count(distinct un.id)=1 then (array_agg(distinct un.id))[1] end uid,
    case when count(distinct un.id)=1 then max(un.name) end uname
   from private.hub_kpi_units_at_date_v1(p_tenant_id,f.dt) un where un.tenant_id=p_tenant_id and un.enabled and un.origin in ('manual','manual_builder') and un.valid_from<=f.dt and (un.valid_to is null or un.valid_to>=f.dt)
   and (f.k<>'cost' or coalesce((f.raw->>'_humla_include_in_vehicle_result')::boolean,true) or un.unit_type='overhead') and (f.proj=any(un.projects) or f.vrn=any(un.registrations) or f.raw->>'employee_id'=any(un.employees) or exists(
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

