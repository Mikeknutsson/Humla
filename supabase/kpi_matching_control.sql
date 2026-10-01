-- Dashboard allocation rules: dated, tenant-scoped, audited; never change amounts.
create table if not exists public.kpi_dashboard_allocations (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.hub_tenants(id),
 dimension text not null check(dimension in ('cost_center','group','unit','vehicle','category','shared_cost')),
 source text not null, kind text not null check(kind in ('revenue','cost')),
 reference_type text not null check(reference_type in ('fact','project','vehicle','article','account')),
 reference text not null check(length(reference) between 1 and 200), target text not null,
 valid_from date not null, valid_to date, reason text not null check(length(reason) between 3 and 1000),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 check(valid_to is null or valid_to>=valid_from),
 unique(tenant_id,dimension,source,kind,reference_type,reference,valid_from)
);
alter table public.kpi_dashboard_allocations drop constraint if exists kpi_dashboard_allocations_dimension_check;
alter table public.kpi_dashboard_allocations add constraint kpi_dashboard_allocations_dimension_check check(dimension in ('cost_center','group','unit','vehicle','category','shared_cost'));
create index if not exists kpi_dashboard_allocations_match_idx on public.kpi_dashboard_allocations(tenant_id,source,kind,reference_type,reference,valid_from);
alter table public.kpi_dashboard_allocations enable row level security;
drop policy if exists kpi_dashboard_allocations_read on public.kpi_dashboard_allocations;
create policy kpi_dashboard_allocations_read on public.kpi_dashboard_allocations for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.manage'));
revoke all on public.kpi_dashboard_allocations from anon,authenticated;
grant select on public.kpi_dashboard_allocations to authenticated;

create or replace function public.hub_kpi_match_save_v1(p_tenant_id uuid,p_items jsonb,p_dimension text,p_target text,p_from date,p_to date,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb; ref text; typ text; src text; k text; affected integer:=0; result_id uuid;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_dimension is null or p_dimension not in ('cost_center','group','unit','vehicle','category','shared_cost') or nullif(trim(p_target),'') is null or p_from is null or (p_to is not null and p_to<p_from) or length(trim(coalesce(p_reason,''))) not between 3 and 1000 or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Kontrollera urval, giltighetsdatum och motivering';end if;
 if p_dimension='shared_cost' and p_target not in ('*','none') and not exists(select 1 from public.kpi_business_groups where tenant_id=p_tenant_id and enabled and name=p_target) then raise exception 'Välj alla enheter eller en giltig verksamhetsgrupp';end if;
 if p_dimension='cost_center' and not exists(select 1 from public.kpi_project_classification_periods where tenant_id=p_tenant_id and cost_center=p_target) then raise exception 'Okänt kostnadsställe';end if;
 if p_dimension='group' and not exists(select 1 from public.kpi_business_groups where tenant_id=p_tenant_id and enabled and name=p_target) then raise exception 'Okänd verksamhetsgrupp';end if;
 if p_dimension='unit' and not exists(select 1 from public.kpi_units where tenant_id=p_tenant_id and id::text=p_target and origin in ('manual','manual_builder') and enabled) then raise exception 'Okänd ekonomisk enhet';end if;
 if p_dimension='vehicle' and p_target !~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then raise exception 'Ange verifierat registreringsnummer';end if;
 if p_dimension='category' and p_target not in ('personnel','fuel','service_repair','fixed','depreciation','material','tipp_deponi','hired','other','transport','tipp') then raise exception 'Okänd kategori';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':kpi-matching',0));
 for item in select value from jsonb_array_elements(p_items) loop
  ref:=trim(item->>'reference');typ:=item->>'reference_type';src:=item->>'source';k:=item->>'kind';
  if typ not in ('fact','project','vehicle','article','account') or src not in ('NEXT','Workify','TransPA','Avskrivningsregister') or k not in ('revenue','cost') or length(coalesce(ref,'')) not between 1 and 200 then raise exception 'Ogiltig referens';end if;
  if p_dimension='shared_cost' and (src<>'NEXT' or k<>'cost' or typ<>'project') then raise exception 'Jämn fördelning gäller NEXT-kostnadsprojekt';end if;
  if exists(select 1 from public.kpi_dashboard_allocations a where a.tenant_id=p_tenant_id and a.dimension=p_dimension and a.source=src and a.kind=k and a.reference_type=typ and a.reference=ref and a.valid_from>=p_from) then raise exception 'En regel finns redan på eller efter startdatumet. Välj ett senare datum.';end if;
  update public.kpi_dashboard_allocations a set valid_to=p_from-1 where a.tenant_id=p_tenant_id and a.dimension=p_dimension and a.source=src and a.kind=k and a.reference_type=typ and a.reference=ref and (a.valid_to is null or a.valid_to>=p_from);
  insert into public.kpi_dashboard_allocations(tenant_id,dimension,source,kind,reference_type,reference,target,valid_from,valid_to,reason,created_by)
  values(p_tenant_id,p_dimension,src,k,typ,ref,p_target,p_from,p_to,trim(p_reason),auth.uid()) returning id into result_id;
  affected:=affected+1;
  -- Release only rows held solely for allocation. Invalid dates/amounts remain held.
  if src='NEXT' and p_dimension in ('cost_center','unit','vehicle','group','shared_cost') then
   update public.kpi_import_rows r set is_valid=true,validation_errors='[]',allocation=coalesce(r.allocation,'{}')||jsonb_build_object('dashboard_allocation_rule',result_id,'allocation_status','classified','reviewed_by',auth.uid(),'reviewed_at',now())
   where r.tenant_id=p_tenant_id and r.data_kind='cost' and not r.is_valid and r.amount is not null and r.occurred_on between p_from and coalesce(p_to,'infinity'::date)
   and r.validation_errors<@'["Kostnadsfördelning behöver granskas","Fordonsbeteckning saknar verifierad regnummerkoppling"]'::jsonb
   and case typ when 'fact' then r.id::text=ref when 'project' then r.project_reference=ref when 'vehicle' then r.vehicle_registration=ref when 'account' then r.account=ref else false end;
  end if;
 end loop;
 update public.kpi_import_batches b set valid_row_count=x.valid,invalid_row_count=x.invalid,status=case when x.invalid>0 then 'needs_review' else 'completed' end
 from (select batch_id,count(*)filter(where is_valid) valid,count(*)filter(where not is_valid) invalid from public.kpi_import_rows where tenant_id=p_tenant_id group by batch_id)x
 where b.id=x.batch_id and b.tenant_id=p_tenant_id and b.status in ('completed','needs_review');
 return jsonb_build_object('saved',affected);
end $$;
revoke all on function public.hub_kpi_match_save_v1(uuid,jsonb,text,text,date,date,text) from public,anon;
grant execute on function public.hub_kpi_match_save_v1(uuid,jsonb,text,text,date,date,text) to authenticated;

CREATE OR REPLACE FUNCTION public.hub_kpi_match_queue_v1(p_tenant_id uuid, p_from date, p_to date, p_dimension text DEFAULT 'cost_center'::text, p_reference_type text DEFAULT 'project'::text, p_search text DEFAULT ''::text, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
AS $function$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_dimension not in ('cost_center','group','unit','vehicle','category','shared_cost') or p_reference_type not in ('project','vehicle','article','account','fact') or p_from is null or p_to<p_from or p_to-p_from>366 or p_page<0 then raise exception 'Ogiltigt urval';end if;
 with facts as materialized(select * from private.hub_kpi_classified_facts_v1(p_tenant_id,p_from,p_to)),
 rows as(
  select fact_id,occurred_on,kind,amount,project,vehicle,account,original,source,description,file_name,row_number from facts where case p_dimension when 'cost_center' then cost_center='unclassified' when 'group' then business_group='Ej klassificerat' when 'unit' then unit_id is null when 'vehicle' then vehicle is null when 'shared_cost' then source='NEXT' and kind='cost' and project is not null else category in ('other','unclassified') end
  union all select r.id::text,r.occurred_on,r.data_kind,r.amount,r.project_reference,r.vehicle_registration,r.account,r.source_data,case when r.data_kind='cost' then 'NEXT' else 'Workify' end,r.description,(select b.file_name from public.kpi_import_batches b where b.id=r.batch_id and b.tenant_id=p_tenant_id),r.row_number
  from public.kpi_import_rows r where r.tenant_id=p_tenant_id and not r.is_valid and r.data_kind in ('cost','revenue') and r.occurred_on between p_from and p_to and (p_dimension<>'shared_cost' or (r.data_kind='cost' and r.project_reference is not null))
 ), keyed as(select rows.*,named.project_name,named.registrations register_vehicles,case p_reference_type when 'project' then project when 'vehicle' then vehicle when 'article' then nullif(original->>'Artikelnummer','') when 'account' then account else fact_id end reference from rows left join lateral(select r.project_name,r.registrations from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and r.project_reference=rows.project and r.valid_from<=rows.occurred_on and (r.valid_to is null or r.valid_to>=rows.occurred_on) order by r.valid_from desc,r.id limit 1)named on true),
 grouped as(select source,kind,coalesce(reference,fact_id) reference,case when reference is null then 'fact' else p_reference_type end reference_type,min(description) description,min(project_name) project_name,
coalesce(jsonb_agg(distinct vehicle)filter(where nullif(vehicle,'') is not null),'[]') vehicles,
coalesce(jsonb_agg(distinct to_jsonb(register_vehicles))filter(where register_vehicles is not null),'[]') register_vehicles,
coalesce(jsonb_agg(distinct jsonb_build_object('reference',project,'name',project_name))filter(where project is not null),'[]') projects,
coalesce(jsonb_agg(distinct account)filter(where account is not null),'[]') accounts,
coalesce(jsonb_agg(distinct original->>'Leverantör')filter(where original->>'Leverantör' is not null),'[]') suppliers,
count(*) rows,round(sum(amount),2) amount,min(occurred_on) first_date,max(occurred_on) last_date from keyed
 where concat_ws(' ',reference,project_name,description,source,account,project,vehicle,register_vehicles::text,original->>'Leverantör') ilike '%'||left(p_search,200)||'%' group by source,kind,coalesce(reference,fact_id),case when reference is null then 'fact' else p_reference_type end),
 page as(select * from grouped order by abs(amount) desc,source,kind,reference limit 100 offset p_page*100)
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('samples',coalesce((select jsonb_agg(to_jsonb(s))from(
select occurred_on,amount,project,project_name,vehicle,account,description,file_name,row_number,original from keyed k
where k.source=p.source and k.kind=p.kind and coalesce(k.reference,k.fact_id)=p.reference and (case when k.reference is null then 'fact' else p_reference_type end)=p.reference_type
order by occurred_on,k.fact_id limit 5)s),'[]')))from page p),'[]'),'total_groups',(select count(*)from grouped),'rows',(select coalesce(sum(rows),0)from grouped),'groups',(select coalesce(jsonb_agg(jsonb_build_object('name',name)order by name),'[]')from public.kpi_business_groups where tenant_id=p_tenant_id and enabled),
 'units',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name)order by name),'[]')from public.kpi_units where tenant_id=p_tenant_id and enabled and origin in ('manual','manual_builder')),
 'cost_centers',(select coalesce(jsonb_agg(to_jsonb(c)order by code),'[]')from(select cost_center code,min(cost_center_name)name from public.kpi_project_classification_periods where tenant_id=p_tenant_id group by cost_center)c),
 'history',(select coalesce(jsonb_agg(to_jsonb(h)),'[]')from(select dimension,source,kind,reference_type,reference,target,valid_from,valid_to,reason,created_at from public.kpi_dashboard_allocations where tenant_id=p_tenant_id order by created_at desc limit 50)h)) into result;
 return result;
end $function$
;
revoke all on function public.hub_kpi_match_queue_v1(uuid,date,date,text,text,text,integer) from public,anon;
grant execute on function public.hub_kpi_match_queue_v1(uuid,date,date,text,text,text,integer) to authenticated;
CREATE OR REPLACE FUNCTION private.hub_kpi_financial_facts_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 then raise exception 'Invalid period'; end if;
 return query
 with allocation_rules as materialized(select * from public.kpi_dashboard_allocations where tenant_id=p_tenant_id and valid_from<=p_to and (valid_to is null or valid_to>=p_from)), unit_versions as materialized (
  select (jsonb_populate_record(null::public.kpi_units,to_jsonb(u)||v.payload||jsonb_build_object('valid_from',v.valid_from,'valid_to',v.valid_to))).*
  from public.kpi_units u join public.kpi_unit_periods v on v.unit_id=u.id and v.tenant_id=u.tenant_id
  where u.tenant_id=p_tenant_id and u.origin in ('manual','manual_builder') and v.valid_from<=p_to and (v.valid_to is null or v.valid_to>=p_from)
  union all select u.* from public.kpi_units u where u.tenant_id=p_tenant_id and u.origin in ('manual','manual_builder')
   and not exists(select 1 from public.kpi_unit_periods v where v.unit_id=u.id)
   and u.valid_from<=p_to and (u.valid_to is null or u.valid_to>=p_from)
 ), unit_group_versions as materialized (
  select p.unit_id,p.valid_from,p.valid_to,g.name
  from public.kpi_unit_periods p join public.kpi_business_groups g
   on g.id::text=p.payload->>'business_group_id' and g.tenant_id=p.tenant_id and g.enabled
  where p.tenant_id=p_tenant_id and p.valid_from<=p_to and (p.valid_to is null or p.valid_to>=p_from)
 ), cfg0 as (
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
   case when x.data_kind='cost' then 'NEXT' else 'Workify' end src,x.description descr,x.account acc,b.file_name fn,x.row_number rn,case when x.data_kind='cost' then x.source_data||jsonb_build_object('_humla_include_in_vehicle_result',cr.include_in_vehicle_result) else x.source_data end || jsonb_build_object('_humla_cost_center',coalesce(nullif(x.cost_center,''),nullif(b.provenance->>'cost_center',''))) raw
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
   case when u.match_count>1 or ug.match_count>1 then 'Ej klassificerat' else coalesce(ug.name,case when f.proj='9009' or f.vrn='LASTBIL' then 'Inhyrda' else coalesce(bg.name,'Ej klassificerat') end) end grp
  from mapped f left join lateral (
   select case when count(distinct un.id)=1 then (array_agg(distinct un.id))[1] end uid,
    case when count(distinct un.id)=1 then max(un.name) end uname,count(distinct un.id) match_count
   from unit_versions un where un.tenant_id=p_tenant_id and un.enabled and un.origin in ('manual','manual_builder') and un.valid_from<=f.dt and (un.valid_to is null or un.valid_to>=f.dt)
   and (f.k<>'cost' or coalesce((f.raw->>'_humla_include_in_vehicle_result')::boolean,true) or un.unit_type='overhead') and (f.proj=any(un.projects) or f.vrn=any(un.registrations) or f.raw->>'employee_id'=any(un.employees) or exists(
    select 1 from public.kpi_unit_components c where c.tenant_id=p_tenant_id and c.unit_id=un.id and c.component_type in ('vehicle','trailer','other') and upper(trim(c.component_reference))=f.vrn and coalesce(c.valid_from,un.valid_from)<=f.dt and (c.valid_to is null or f.dt<=c.valid_to)))
  ) u on true
  left join lateral (
   select count(distinct g.name) match_count,case when count(distinct g.name)=1 then max(g.name) end name
   from unit_group_versions g where g.unit_id=u.uid and g.valid_from<=f.dt and (g.valid_to is null or g.valid_to>=f.dt)
  ) ug on true
  left join lateral (
   select case when count(distinct p.business_group_id)=1 then (array_agg(distinct p.business_group_id))[1] end gid
   from public.kpi_project_business_groups p where p.tenant_id=p_tenant_id and p.project_reference=f.proj and f.dt>=coalesce(p.valid_from,'2000-01-01') and (p.valid_to is null or f.dt<=p.valid_to)
  ) pg on true left join public.kpi_business_groups bg on bg.id=pg.gid and bg.tenant_id=p_tenant_id and bg.enabled
 ), decorated as(select f.fid,f.dt,f.k,f.amt,coalesce(a.targets->>'category',f.cat) cat,f.proj,coalesce(a.targets->>'vehicle',f.vrn) vrn,coalesce(assigned.id,f.uid) uid,coalesce(assigned.name,f.uname) uname,
coalesce(a.targets->>'group',assigned.grp,f.grp) grp,f.src,f.descr,f.acc,f.fn,f.rn,f.raw||jsonb_build_object('_humla_assignment',a.targets) raw
from related f left join lateral(
 select jsonb_object_agg(dimension,target) targets from(
 select distinct on (dimension) dimension,target from allocation_rules r where r.source=f.src and r.kind=f.k and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt)
 and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=f.proj when 'vehicle' then r.reference=f.vrn when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc else false end
 order by dimension,case r.reference_type when 'fact' then 1 when 'project' then 2 when 'vehicle' then 3 when 'article' then 4 else 5 end,r.valid_from desc,r.created_at desc
 ) matching
) a on true left join lateral(
 select u.id,u.name,(select g.name from unit_group_versions g where g.unit_id=u.id and g.valid_from<=f.dt and (g.valid_to is null or g.valid_to>=f.dt) limit 1) grp from unit_versions u
 where u.id::text=a.targets->>'unit' and u.enabled and u.valid_from<=f.dt and (u.valid_to is null or u.valid_to>=f.dt) limit 1
) assigned on true
)
 select case when recipients.id is null then f.fid else f.fid||':share:'||recipients.id::text end,f.dt,f.k,
 case when recipients.id is null then f.amt when recipients.position=recipients.n then f.amt-round(f.amt/recipients.n,2)*(recipients.n-1) else round(f.amt/recipients.n,2) end,
 f.cat,f.proj,case when recipients.id is not null then case when recipients.name ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then recipients.name end when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then null else f.vrn end,
 case when recipients.id is not null then recipients.id when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then null else f.uid end,
 case when recipients.id is not null then recipients.name when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then null else f.uname end,
 case when recipients.id is not null then coalesce(recipients.grp,'Ej klassificerat') when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then 'Ej klassificerat' else f.grp end,
 f.src,f.descr,f.acc,f.fn,f.rn,
 f.raw||case when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then jsonb_build_object('_humla_distribution',jsonb_build_object('method','equal','scope',f.raw#>>'{_humla_assignment,shared_cost}','original_fact_id',f.fid,'original_amount',f.amt,'recipient_count',coalesce(recipients.n,0),'recipient_unit',recipients.id,'status',case when recipients.id is null then 'no_eligible_units' else 'allocated' end)) else '{}'::jsonb end
 from decorated f left join lateral(
 select eligible.*,count(*)over() n,row_number()over(order by eligible.id) position
 from (
  select distinct on(u.id) u.id,u.name,coalesce(own.name,registry.name) grp from unit_versions u
  left join lateral(select name from unit_group_versions g where g.unit_id=u.id and g.valid_from<=f.dt and (g.valid_to is null or g.valid_to>=f.dt) order by g.valid_from desc limit 1)own on true
  left join lateral(
   select case when count(distinct r.business_group)=1 then min(r.business_group) end name from public.kpi_project_classification_periods r
   where r.tenant_id=p_tenant_id and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt) and u.name=any(r.registrations) and r.business_group is not null
  )registry on own.name is null
  where f.k='cost' and f.src='NEXT' and f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','')
  and u.enabled and u.valid_from<=f.dt and (u.valid_to is null or u.valid_to>=f.dt)
  and (f.raw#>>'{_humla_assignment,shared_cost}'='*' or coalesce(own.name,registry.name)=f.raw#>>'{_humla_assignment,shared_cost}')
  order by u.id,u.valid_from desc
 )eligible
 )recipients on true;
end $function$;
CREATE OR REPLACE FUNCTION private.hub_kpi_classified_facts_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb, cost_center text, cost_center_name text, classification_source jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with facts as materialized(select * from private.hub_kpi_financial_facts_v1(p_tenant_id,p_from,p_to)),
 registry as materialized(select * from public.kpi_project_classification_periods where tenant_id=p_tenant_id and valid_from<=p_to and (valid_to is null or valid_to>=p_from))
 select f.fact_id,f.occurred_on,f.kind,f.amount,f.category,f.project,f.vehicle,f.unit_id,f.unit_name,
  case when f.original#>>'{_humla_distribution,status}' in ('allocated','no_eligible_units') then f.business_group when nullif(f.original#>>'{_humla_assignment,group}','') is not null then f.business_group when own_group.has_group then f.business_group when explicit_group.has_group then f.business_group
   when cc.center_count>1 or bg.group_count>1 then 'Ej klassificerat' else coalesce(bg.group_name,f.business_group) end,
  f.source,f.description,f.account,f.file_name,f.row_number,f.original,
  coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),article.cost_center,nullif(f.original->>'_humla_cost_center',''),case when cc.center_count=1 then cc.code else 'unclassified' end),
  case when coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),nullif(f.original->>'_humla_cost_center','')) is not null then coalesce((select min(r.cost_center_name) from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and r.cost_center=coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),f.original->>'_humla_cost_center')),f.original->>'_humla_cost_center') when article.cost_center is not null then coalesce((select min(r.cost_center_name) from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and r.cost_center=article.cost_center),article.cost_center) when cc.center_count=1 then cc.name else 'Ej klassificerat' end,
  jsonb_build_object('registry_sources',cc.sources,'article_rule_id',article.id,'manual_assignment',f.original->'_humla_assignment','reason',case when f.original#>>'{_humla_assignment,cost_center}' is not null then 'manual_dated_assignment' when f.original->>'_humla_cost_center' is not null then 'verified_import_cost_center' when article.cost_center is not null then 'exact_dated_article_rule' when cc.center_count>1 then 'conflicting_cost_centers' when cc.center_count=0 then 'missing_cost_center' else 'exact_dated_reference' end)
 from facts f
 -- A verified dated article rule classifies revenue even without a vehicle/project.
 -- Vehicle identity and group matching retain their existing dated rules.
 left join lateral(
  select a.id,nullif(trim(a.cost_center),'') cost_center
  from public.kpi_workify_article_rules a
  where f.source='Workify' and a.tenant_id=p_tenant_id and a.enabled
   and a.article_number=coalesce(f.original->>'Artikelnummer','')
   and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)
  order by a.valid_from desc,a.id limit 1
 ) article on true
 left join lateral(
  select count(distinct r.cost_center) center_count,min(r.cost_center) code,min(r.cost_center_name) name,jsonb_agg(distinct r.source) sources
  from registry r where r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
  and (r.project_reference=f.project or f.vehicle=any(r.registrations) or (f.source='TransPA' and r.project_reference=f.original->>'employee_id'))
 ) cc on true
 left join lateral(
  with candidates as(select r.business_group,case when r.project_reference=f.project then 1 when f.vehicle=any(r.registrations) then 2 else 3 end priority
   from registry r where r.business_group is not null and r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
   and (r.project_reference=f.project or f.vehicle=any(r.registrations) or (f.source='TransPA' and r.project_reference=f.original->>'employee_id')))
  select count(distinct business_group) group_count,case when count(distinct business_group)=1 then min(business_group) end group_name from candidates where priority=(select min(priority) from candidates)
 ) bg on true
 left join lateral(select exists(select 1 from public.kpi_unit_periods p where p.tenant_id=p_tenant_id and p.unit_id=f.unit_id and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on) and nullif(p.payload->>'business_group_id','') is not null) has_group) own_group on true
 left join lateral(select exists(select 1 from public.kpi_project_business_groups p where p.tenant_id=p_tenant_id and p.project_reference=f.project and p.source='kpi_admin_dated' and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)) has_group) explicit_group on true;
$function$;
CREATE OR REPLACE FUNCTION private.hub_kpi_month_snapshot_v1(p_tenant_id uuid, p_fiscal_year integer, p_selected_months integer[], p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare output jsonb; months integer[]; fy_from date; fy_to date;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501'; end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);
 fy_from:=make_date(p_fiscal_year,9,1);fy_to:=make_date(p_fiscal_year+1,8,31);
 with selected_facts as materialized(select * from private.hub_kpi_month_facts_v1(p_tenant_id,p_fiscal_year,months,p_filters-'cost_center')),
 facts as materialized(select * from selected_facts where not(p_filters?'cost_center') or cost_center=p_filters->>'cost_center'),
 month_dates as(select m,make_date(case when m>=9 then p_fiscal_year else p_fiscal_year+1 end,m,1) dt from unnest(months) m),
 monthly as(select m,dt,coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost,count(f.fact_id) rows from month_dates left join facts f on date_trunc('month',f.occurred_on)::date=dt group by m,dt),
 cats as(select category,round(sum(amount),2) amount from facts where kind='cost' group by category),
 totals as(select coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost,
 coalesce(sum(amount) filter(where kind='revenue' and vehicle='LASTBIL'),0) hired,
 count(distinct vehicle) filter(where kind='revenue' and amount<>0 and vehicle not in ('LASTBIL','Ej fördelat')) vehicles from facts),
 groups as(select business_group key,business_group label,count(*) rows,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by business_group),
 units as(select coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') key,max(coalesce(unit_name,vehicle,'Ej fördelat')) label,count(*) rows,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by 1),
 unit_children as(select coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') unit_key,coalesce(vehicle,'project:'||project,'unassigned') key,max(coalesce(vehicle,project,'Ej fördelat')) label,max(vehicle) vehicle,max(project) project,count(*) rows,round(coalesce(sum(amount)filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount)filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result from facts group by 1,2),
 all_daily as materialized(select * from public.kpi_transpa_vehicle_time_daily_secure(p_tenant_id,date '2000-01-01',fy_to)),
 first_seen as(select vehicle_id,min(work_date) first_seen from all_daily group by vehicle_id),
 daily as materialized(select d.*,upper(trim(split_part(vehicle_name,' ',1))) reg from all_daily d
 where d.work_date between fy_from and fy_to and extract(month from d.work_date)::int=any(months)
 and upper(trim(split_part(vehicle_name,' ',1)))~'^[A-Z]{3}[0-9]{2}[A-Z0-9]$'
 and (p_filters='{}'::jsonb or exists(select 1 from facts f where f.source='TransPA' and f.occurred_on=d.work_date and f.vehicle=upper(trim(split_part(d.vehicle_name,' ',1)))))),
 vehicle_time_base as(select d.vehicle_id,max(d.reg) vehicle,sum(d.reported_vehicle_hours)::numeric hours,sum(d.time_reports) time_reports,min(fs.first_seen) first_seen from daily d join first_seen fs using(vehicle_id) group by d.vehicle_id),
 vehicle_time as(select v.*,(select count(*)::numeric from generate_series(greatest(fy_from,v.first_seen),fy_to,interval '1 day') d where extract(month from d)::int=any(months) and extract(isodow from d) between 1 and 5 and not public.hub_is_swedish_public_holiday(d::date)
 and (p_filters='{}'::jsonb or exists(select 1 from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and v.vehicle=any(r.registrations) and r.valid_from<=d::date and (r.valid_to is null or r.valid_to>=d::date) and (not(p_filters?'cost_center') or r.cost_center=p_filters->>'cost_center') and (not(p_filters?'group') or r.business_group=p_filters->>'group')))) * coalesce((select s.vehicle_capacity_hours_per_day::numeric from public.kpi_settings s where s.tenant_id=p_tenant_id),8) available_hours from vehicle_time_base v),
 time_totals as(select coalesce(sum(hours),0) hours,coalesce(sum(available_hours),0) available,count(*) vehicles from vehicle_time),
 next_daily as(select n.occurred_on work_date,upper(trim(n.vehicle_registration)) vehicle,sum(n.paid_hours) hours from public.kpi_import_rows n where n.tenant_id=p_tenant_id and n.is_valid and n.data_kind='next_historical_time' and n.occurred_on between fy_from and fy_to and extract(month from n.occurred_on)::int=any(months)
 and upper(trim(coalesce(n.description,'')))=any(array['K.CH','L.CH','MA','UEA','UEM','ÖT-1','ÖT-2','ÖT-3','ÖT-4','ÖT-5','ÖT-6']) and upper(trim(n.vehicle_registration))~'^[A-Z]{3}[0-9]{2}[A-Z0-9]$'
 and (p_filters='{}'::jsonb or exists(select 1 from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and r.project_reference=n.project_reference and r.valid_from<=n.occurred_on and (r.valid_to is null or r.valid_to>=n.occurred_on) and (not(p_filters?'cost_center') or r.cost_center=p_filters->>'cost_center') and (not(p_filters?'group') or r.business_group=p_filters->>'group')))
 group by 1,2),
 worked as(select tt.hours+coalesce((select sum(n.hours) from next_daily n where not exists(select 1 from daily d where d.work_date=n.work_date and d.reg=n.vehicle)),0) hours from time_totals tt),
 revenue_days as materialized(select f.occurred_on work_date,array_agg(distinct e.external_id) vehicle_ids from facts f join public.hub_transpa_entities e on e.tenant_id=p_tenant_id and e.entity_type='vehicle' and public.hub_normalize_vehicle_registration(e.payload->>'registrationNumber')=f.vehicle where f.kind='revenue' and f.amount<>0 group by f.occurred_on),
 eligible_time as materialized(select distinct original->>'time_report_id' report_id from facts where source='TransPA'),
 driver_time as(select t.employee_id,t.work_hours,coalesce(t.transpa_vehicle_ids ?| rd.vehicle_ids,false) productive
 from public.kpi_transpa_time_facts t left join revenue_days rd on rd.work_date=t.work_date
 where t.tenant_id=p_tenant_id and t.work_date between fy_from and fy_to and extract(month from t.work_date)::int=any(months)
 and (p_filters='{}'::jsonb or t.time_report_id::text in(select report_id from eligible_time))),
 drivers as(select employee_id driver,employee_id,sum(work_hours)::numeric total_hours,coalesce(sum(work_hours) filter(where productive),0)::numeric productive_hours,coalesce(sum(work_hours) filter(where not productive),0)::numeric unclassified_hours from driver_time group by employee_id),
 driver_totals as(select coalesce(sum(total_hours),0) hours,coalesce(sum(productive_hours),0) productive,coalesce(sum(unclassified_hours),0) unclassified from drivers),
 vehicles as(select coalesce(f.vehicle,'Ej fördelat') vehicle,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,round(sum(case when kind='revenue' then amount else -amount end),2) result,round(coalesce(sum(amount) filter(where category='fuel' and kind='cost'),0),2) fuel_cost,round(coalesce(sum(amount) filter(where source='TransPA'),0),2) personnel_cost from facts f group by f.vehicle)
 select jsonb_build_object(
 'hub_contract_version','fiscal-months-v1','period',jsonb_build_object('fiscal_year',p_fiscal_year,'selected_months',months,'from',fy_from,'to',fy_to),'filters',p_filters,
 'coverage',(select jsonb_build_object('revenue_months',coalesce(jsonb_agg(m)filter(where revenue_rows>0),'[]'),'cost_months',coalesce(jsonb_agg(m)filter(where next_rows>0),'[]'))from(select m,count(f.fact_id)filter(where f.source='Workify') revenue_rows,count(f.fact_id)filter(where f.source='NEXT')next_rows from unnest(months)m left join selected_facts f on extract(month from f.occurred_on)::int=m group by m)x),
 'metrics',jsonb_build_object('revenue',round(t.revenue,2),'total_cost',round(t.cost,2),'result',round(t.revenue-t.cost,2),'margin_pct',round((t.revenue-t.cost)/nullif(t.revenue,0)*100,2),'revenue_per_vehicle',round(t.revenue/nullif(t.vehicles,0),2),'diesel_share',round(coalesce((select amount from cats where category='fuel'),0)/nullif(t.revenue,0)*100,2),'vehicle_utilization',round(tt.hours/nullif(tt.available,0)*100,1)),
 'components',(select jsonb_build_object('next_total_cost',round(coalesce(sum(amount) filter(where source='NEXT'),0),2),'transpa_personnel_cost',round(coalesce(sum(amount) filter(where source='TransPA'),0),2),'depreciation_cost',round(coalesce(sum(amount) filter(where kind='cost' and category='depreciation'),0),2)) from facts),
 'monthly',(select jsonb_agg(jsonb_build_object('month',m,'period_start',dt,'period_end',(dt+interval '1 month'-interval '1 day')::date,'revenue',round(revenue,2),'cost',round(cost,2),'result',round(revenue-cost,2),'rows',rows) order by dt) from monthly),
 'business_groups',coalesce((select jsonb_agg(to_jsonb(g) order by label) from groups g),'[]'),
 'group_options',(select jsonb_agg(name order by name)from(select name from public.kpi_business_groups where tenant_id=p_tenant_id and enabled union select business_group from public.kpi_project_classification_periods where tenant_id=p_tenant_id and business_group is not null union select 'Ej klassificerat') names),
 'economic_units',coalesce((select jsonb_agg(to_jsonb(u)||jsonb_build_object('children',coalesce((select jsonb_agg(to_jsonb(c) order by label)from unit_children c where c.unit_key=u.key),'[]')) order by label) from units u),'[]'),
 'cost_categories',coalesce((select jsonb_object_agg(category,amount) from cats),'{}'),
 'vehicles',coalesce((select jsonb_agg(to_jsonb(v)||jsonb_build_object('occupied_hours',vt.hours,'available_hours',vt.available_hours,'utilization',round(vt.hours/nullif(vt.available_hours,0)*100,1),'revenue_per_hour',round(v.revenue/nullif(vt.hours,0),2)) order by v.vehicle) from vehicles v left join vehicle_time vt using(vehicle)),'[]'),
 'drivers',coalesce((select jsonb_agg(to_jsonb(d)) from drivers d),'[]'),'unmapped_accounts','[]'::jsonb,
 'unclassified_summary',(select jsonb_build_object('revenue',round(coalesce(sum(amount) filter(where kind='revenue'),0),2),'cost',round(coalesce(sum(amount) filter(where kind='cost'),0),2),'rows',count(*)) from selected_facts where cost_center='unclassified'),
 'quality',(select jsonb_build_object('total_rows',count(*),'valid_rows',count(*),'rows_without_vehicle',count(*) filter(where vehicle is null),'rows_without_employee',0,'rows_without_account_mapping',0,'basis','Hub authoritative financial facts') from facts),
 'transpa_vehicle_time',jsonb_build_object('reported_hours',round(tt.hours,2),'available_hours',round(tt.available,2),'vehicle_count',tt.vehicles,'utilization',round(tt.hours/nullif(tt.available,0)*100,1),'vehicles',coalesce((select jsonb_agg(to_jsonb(v)||jsonb_build_object('occupied_hours',hours,'utilization',round(hours/nullif(available_hours,0)*100,1))) from vehicle_time v),'[]')),
 'efficiency',jsonb_build_object('worked_hours',round(w.hours,2),'revenue',round(t.revenue,2),'own_revenue',round(t.revenue-t.hired,2),'hired_revenue',round(t.hired,2),'revenue_per_worked_hour',round((t.revenue-t.hired)/nullif(w.hours,0),2)),
 'hired_capacity',jsonb_build_object('total_revenue',round(t.revenue,2),'hired_revenue',round(t.hired,2),'hired_share_percent',round(t.hired/nullif(t.revenue,0)*100,2)),
 'driver_productivity',jsonb_build_object('total_hours',round(d.hours,2),'productive_hours',round(d.productive,2),'unclassified_hours',round(d.unclassified,2),'productive_percent',round(d.productive/nullif(d.hours,0)*100,1),'drivers',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('productive_percent',round(productive_hours/nullif(total_hours,0)*100,1))) from drivers x),'[]')),
 'cost_efficiency',coalesce((select jsonb_object_agg(category||'_cost_per_hour',round(amount/nullif(w.hours,0),2)) from cats),'{}')||jsonb_build_object('worked_hours',round(w.hours,2),'total_cost_per_hour',round(t.cost/nullif(w.hours,0),2),'result_per_hour',round((t.revenue-t.cost)/nullif(w.hours,0),2),'direct_cost_per_hour',null,'common_cost_per_hour',null,'overhead_cost_per_hour',null,'contribution_per_hour',null),
 'personnel_basis','TransPA-tid × Hub-schablon; inte verifierad löneexport',
 'reconciliation',jsonb_build_object('matches',t.revenue=(select sum(revenue) from monthly) and t.cost=(select sum(cost) from monthly),'vehicle_rows_match',abs(round(t.revenue,2)-(select coalesce(sum(revenue),0) from vehicles))<=0.01*(select count(*) from vehicles) and abs(round(t.cost,2)-(select coalesce(sum(cost),0) from vehicles))<=0.01*(select count(*) from vehicles),'source','Hub authoritative classified facts, exact selected months')
 ) into output from totals t cross join time_totals tt cross join worked w cross join driver_totals d;
 return output;
end $function$;
notify pgrst,'reload schema';
