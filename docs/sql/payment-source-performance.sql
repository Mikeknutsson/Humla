CREATE OR REPLACE FUNCTION private.hub_kpi_financial_source_facts_v1(p_tenant_id uuid, p_from date, p_to date, p_months integer[], p_sources text[])
 RETURNS TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
 SET plan_cache_mode TO 'force_custom_plan'
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
 times as (select t.*,date_trunc('week',work_date)::date wk from public.kpi_transpa_time_facts t where (p_sources is null or 'TransPA'=any(p_sources)) and t.tenant_id=p_tenant_id and work_date between p_from and p_to and work_hours>0),
 weeks as (select employee_id,wk,sum(work_hours) hours from times group by 1,2),
 payroll as (
  select t.*,(case when w.hours<=c.wh then t.work_hours else t.work_hours*c.wh/w.hours end +
   case when w.hours<=c.wh then 0 else t.work_hours*(w.hours-c.wh)/w.hours*c.ot end)*private.hub_person_cost_salary_v1(p_tenant_id,(select k.object_id from public.hub_identity_keys k where k.tenant_id=p_tenant_id and k.identity_type='transpa_employee_id'and k.identity_value=t.employee_id and k.confidence=1 limit 1),t.work_date,c.salary)/(c.wh*52/12)*c.load pc
  from times t join weeks w using(employee_id,wk) cross join cfg c
 ), imports as materialized (
  select x.id::text fid,x.occurred_on dt,x.data_kind k,x.amount amt,
   case when x.data_kind='revenue' then coalesce(ar.revenue_category,'unclassified')
    when x.project_reference='9009' and cr.cost_category='material' then 'material' when x.project_reference='9009' then 'hired' when x.project_reference='5100' then 'tipp_deponi'
    when x.account in ('5360','5621','5631') then 'fuel' else coalesce(cr.cost_category,'other') end cat,
   case when x.data_kind='revenue' and private.hub_is_next_ledger_revenue_v1(x.source_data) then coalesce(nullif(trim(x.project_reference),''),trim(x.source_data->>'Projektnr')) when x.data_kind='revenue' then case when nullif(x.allocation->>'project_carrier_reference','') is not null then x.allocation->>'project_carrier_reference' when ov.order_name is not null then null when ar.target_type='project' then private.hub_kpi_project_reference_v1(p_tenant_id,ar.project_reference) else null end
    else coalesce(nullif(x.allocation->>'allocation_reference',''),x.project_reference) end proj,
   case when x.data_kind='revenue' and nullif(x.allocation->>'project_carrier_reference','') is null and (ov.order_name is not null or coalesce(ar.target_type,'vehicle')='vehicle') then case when ov.order_name is not null then case when upper(trim(x.vehicle_registration)) ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then upper(trim(x.vehicle_registration)) end else upper(trim(x.vehicle_registration)) end
    when x.data_kind='cost' then null else null end reg,
   case when x.data_kind='cost' or private.hub_is_next_ledger_revenue_v1(x.source_data) then 'NEXT' else 'Workify' end src,x.description descr,case when x.data_kind='revenue' and private.hub_is_next_ledger_revenue_v1(x.source_data) then coalesce(nullif(x.account,''),x.source_data->>'Konto') else x.account end acc,b.file_name fn,x.row_number rn,case when x.data_kind='cost' then private.hub_next_completion_source_v1(x.id,x.source_data)||jsonb_build_object('_humla_include_in_vehicle_result',cr.include_in_vehicle_result) else private.hub_workify_reporting_source_v1(x.id,x.source_data,x.is_valid) end || case when ov.order_name is not null then jsonb_build_object('_humla_order_vehicle_rule',ov.order_name,'_humla_order_vehicle_status',case when nullif(trim(x.vehicle_registration),'') is null then 'missing_vehicle' when upper(trim(x.vehicle_registration)) ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then 'matched' else 'invalid_vehicle' end) else '{}'::jsonb end || jsonb_build_object('_humla_project_fallback',x.allocation->'project_carrier_fallback') || jsonb_build_object('_humla_cost_center',coalesce(nullif(x.cost_center,''),nullif(b.provenance->>'cost_center',''))) raw
  from public.kpi_import_rows x join public.kpi_import_batches b on b.id=x.batch_id
  left join lateral (select a.* from public.kpi_workify_article_rules a where a.tenant_id=p_tenant_id and a.enabled and a.article_number=coalesce(x.source_data->>'Artikelnummer','') and x.occurred_on>=a.valid_from and (a.valid_to is null or x.occurred_on<=a.valid_to) order by a.valid_from desc,a.id limit 1) ar on not private.hub_is_next_ledger_revenue_v1(x.source_data)
  left join lateral (
   select r.order_name from private.hub_kpi_workify_order_vehicle_rules r
   where x.data_kind='revenue' and r.tenant_id=p_tenant_id and r.enabled
    and r.valid_from<=x.occurred_on and (r.valid_to is null or r.valid_to>=x.occurred_on)
    and r.order_name=lower(regexp_replace(trim(coalesce(nullif(x.project_reference,''),x.source_data->>'Littranummer','')),'\s+',' ','g'))
   order by r.valid_from desc limit 1
  ) ov on not private.hub_is_next_ledger_revenue_v1(x.source_data)
  left join lateral (select r.cost_category,r.include_in_vehicle_result from public.kpi_cost_category_rules r where r.tenant_id=p_tenant_id and r.account=x.account and x.occurred_on>=r.valid_from and (r.valid_to is null or x.occurred_on<=r.valid_to) order by r.valid_from desc,r.id limit 1) cr on true
  where (p_sources is null or (case when x.data_kind='cost' or private.hub_is_next_ledger_revenue_v1(x.source_data) then 'NEXT' else 'Workify' end)=any(p_sources)) and x.tenant_id=p_tenant_id and (case when x.data_kind='revenue' and x.source_data ? 'Ordernummer' then
  x.occurred_on is not null and x.amount is not null and x.amount<>0 and x.amount::text not in ('NaN','Infinity','-Infinity')
  and nullif(trim(x.source_data->>'Ordernummer'),'') is not null
  and private.hub_workify_financially_eligible_v1(x.is_valid,x.validation_errors)
  and private.hub_workify_row_in_scope_v1(x.id,x.source_data)
 else (coalesce(x.is_valid,false) or (x.data_kind='cost' and (case when jsonb_typeof(coalesce(x.validation_errors,'[]'))<>'array' then false else
 not exists(select 1 from jsonb_array_elements_text(coalesce(x.validation_errors,'[]'))e
 where e not in('Kostnadsfördelning behöver granskas','Fordonsbeteckning saknar verifierad regnummerkoppling'))
 and exists(select 1 from private.hub_next_completeness_items i
 join public.kpi_import_rows r on r.id=i.row_id and r.tenant_id=i.tenant_id
 join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 where i.row_id=x.id and i.occurred_on=x.occurred_on and i.amount=x.amount and r.data_kind='cost'
 and b.status in('completed','needs_review') and not(coalesce(b.provenance,'{}')?'withdrawal')) end))) and (x.data_kind<>'revenue' or x.amount<>0)
 and (x.data_kind<>'cost' or not exists(select 1 from private.hub_next_reexport_audit where row_id=x.id)) end) and coalesce(ar.revenue_category,'')<>'ignored' and x.data_kind in ('revenue','cost') and x.occurred_on between p_from and p_to and (p_months is null or extract(month from x.occurred_on)::int=any(p_months))
 ), raw_facts as (
  select * from imports
  union all
  select 'transpa:'||t.time_report_id||':'||coalesce(j.ordinality,0),t.work_date,'cost',t.pc/greatest(jsonb_array_length(coalesce(t.transpa_vehicle_ids,'[]')),1),
   'personnel',null,upper(trim(v.payload->>'registrationNumber')),'TransPA',
   'Beräknad personalkostnad från TransPA-tid (Hub-schablon)',null,null,null,
   jsonb_build_object('time_report_id',t.time_report_id,'employee_id',t.employee_id,'work_date',t.work_date,'work_hours',t.work_hours,'report_status',t.report_status,'calculation','hub_kpi_personnel_costs_engine_v1','actual_payroll',false)
  from payroll t left join lateral jsonb_array_elements(t.transpa_vehicle_ids) with ordinality j(value,ordinality) on true
  left join public.hub_transpa_entities v on v.tenant_id=p_tenant_id and v.entity_type='vehicle' and v.external_id=j.value#>>'{}'
  where p_months is null or extract(month from t.work_date)::int=any(p_months)
  union all
  select 'depreciation:'||d.id||':'||gs::date,greatest(gs::date,p_from,d.valid_from),'cost',d.monthly_depreciation,'depreciation',null,upper(trim(d.object_reference)),'Avskrivningsregister',
   'Månadsavskrivning',null,null,null,jsonb_build_object('register_id',d.id,'valid_from',d.valid_from,'valid_to',d.valid_to,'monthly_depreciation',d.monthly_depreciation)
  from public.kpi_asset_depreciation_periods d cross join lateral generate_series(date_trunc('month',greatest(p_from,d.valid_from)),date_trunc('month',least(p_to,coalesce(d.valid_to,p_to))),interval '1 month') gs
  where (p_sources is null or 'Avskrivningsregister'=any(p_sources)) and d.tenant_id=p_tenant_id and d.valid_from<=p_to and (d.valid_to is null or d.valid_to>=p_from) and (p_months is null or extract(month from greatest(gs::date,p_from,d.valid_from))::int=any(p_months))
 ), routed as materialized (
  select f.fid,f.dt,f.k,f.amt,f.cat,coalesce(a.target,f.proj) proj,coalesce(v.target,f.reg) reg,f.src,f.descr,f.acc,f.fn,f.rn,
   f.raw||case when a.target is not null then jsonb_build_object('_humla_original_project',f.proj,'_humla_project_assignment',a.target) else '{}'::jsonb end||case when v.target is not null then jsonb_build_object('_humla_original_registration',f.reg,'_humla_vehicle_assignment',v.target) else '{}'::jsonb end raw
  from raw_facts f left join lateral(
   select r.target from allocation_rules r
   where r.dimension='project' and r.source=f.src and r.kind=f.k and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt)
   and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=f.proj when 'vehicle' then r.reference=coalesce(nullif(f.reg,''),(select case when count(distinct upper(trim(pm.vehicle_registration)))=1 then max(upper(trim(pm.vehicle_registration))) end from (select project_reference,vehicle_registration,valid_from,valid_to,true enabled,tenant_id from public.kpi_project_vehicle_periods where tenant_id=p_tenant_id union all select project_reference,vehicle_registration,valid_from,valid_to,enabled,tenant_id from public.kpi_project_unit_mappings legacy where tenant_id=p_tenant_id and not exists(select 1 from public.kpi_project_vehicle_periods h where h.tenant_id=p_tenant_id and h.project_reference=legacy.project_reference)) pm where pm.enabled and pm.project_reference=f.proj and f.dt>=coalesce(pm.valid_from,'2000-01-01') and (pm.valid_to is null or f.dt<=pm.valid_to))) when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc when 'supplier' then f.src='NEXT' and f.k='cost' and upper(trim(r.reference))=upper(trim(f.raw->>'Leverantör')) else false end
   order by case r.reference_type when 'fact' then 1 when 'supplier' then 2 when 'project' then 3 when 'vehicle' then 4 when 'article' then 5 else 6 end,r.valid_from desc,r.created_at desc limit 1
  ) a on true
  left join lateral(
   select r.target from allocation_rules r
   where r.dimension='vehicle' and r.source=f.src and r.kind=f.k and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt)
   and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=f.proj when 'vehicle' then r.reference=f.reg when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc when 'supplier' then f.src='NEXT' and f.k='cost' and upper(trim(r.reference))=upper(trim(f.raw->>'Leverantör')) else false end
   order by case r.reference_type when 'fact' then 1 when 'supplier' then 2 when 'project' then 3 when 'vehicle' then 4 when 'article' then 5 else 6 end,r.valid_from desc,r.created_at desc limit 1
  ) v on true
 ), mapped as materialized (
  select f.*,case when f.raw->>'_humla_project_fallback'='true' then null when f.k='cost' and f.raw->>'_humla_include_in_vehicle_result'='false' then null when f.proj='9009' or f.reg='LASTBIL' then 'LASTBIL' else coalesce(nullif(f.reg,''),m.reg) end vrn
  from routed f left join lateral (
   select case when count(distinct upper(trim(vehicle_registration)))=1 then max(upper(trim(vehicle_registration))) end reg
   from (select project_reference,vehicle_registration,valid_from,valid_to,true enabled,tenant_id from public.kpi_project_vehicle_periods where tenant_id=p_tenant_id union all select project_reference,vehicle_registration,valid_from,valid_to,enabled,tenant_id from public.kpi_project_unit_mappings legacy where tenant_id=p_tenant_id and not exists(select 1 from public.kpi_project_vehicle_periods h where h.tenant_id=p_tenant_id and h.project_reference=legacy.project_reference)) pm where pm.tenant_id=p_tenant_id and pm.enabled and pm.project_reference=f.proj and f.dt>=coalesce(pm.valid_from,'2000-01-01') and (pm.valid_to is null or f.dt<=pm.valid_to)
  ) m on true
 ), mapped_keyed as materialized (
 select m.*,jsonb_build_array(m.dt,m.k,m.proj,m.vrn,m.raw->>'employee_id',m.raw->>'_humla_include_in_vehicle_result') match_key from mapped m
 ), matching_keys as materialized (
 select distinct match_key,dt,k,proj,vrn,jsonb_build_object('employee_id',raw->>'employee_id','_humla_include_in_vehicle_result',raw->>'_humla_include_in_vehicle_result') raw from mapped_keyed
 ), identity_resolution as materialized (
  select f.match_key,u.uid,u.uname,u.match_count unit_match_count,ug.match_count unit_group_match_count,
   case when u.match_count>1 or ug.match_count>1 then 'Ej klassificerat' else coalesce(ug.name,case when f.proj='9009' or f.vrn='LASTBIL' then 'Inhyrda' else coalesce(bg.name,'Ej klassificerat') end) end grp
  from matching_keys f left join lateral (
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
 ), related as (
 select f.*,r.uid,r.uname,r.unit_match_count,r.unit_group_match_count,r.grp
 from mapped_keyed f join identity_resolution r on r.match_key=f.match_key
 ), decorated as materialized (select f.fid,f.dt,f.k,f.amt,coalesce(a.targets->>'category',f.cat) cat,f.proj,coalesce(a.targets->>'vehicle',f.vrn) vrn,coalesce(assigned.id,f.uid) uid,coalesce(assigned.name,f.uname) uname,
coalesce(a.targets->>'group',assigned.grp,f.grp) grp,f.src,f.descr,f.acc,f.fn,f.rn,f.raw||jsonb_build_object('_humla_assignment',a.targets,'_humla_identity_resolution',jsonb_build_object('unit_matches',f.unit_match_count,'group_matches',f.unit_group_match_count)) raw
from related f left join lateral(
 select jsonb_object_agg(dimension,target) targets from(
 select distinct on (dimension) dimension,target from allocation_rules r where r.source=f.src and r.kind=f.k and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt)
 and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=case when f.raw?'_humla_original_project' then f.raw->>'_humla_original_project' else f.proj end when 'vehicle' then (r.reference=f.vrn or r.reference=f.raw->>'_humla_original_registration') when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc when 'supplier' then f.src='NEXT' and f.k='cost' and upper(trim(r.reference))=upper(trim(f.raw->>'Leverantör')) else false end
 order by dimension,case r.reference_type when 'fact' then 1 when 'supplier' then 2 when 'project' then 3 when 'vehicle' then 4 when 'article' then 5 else 6 end,r.valid_from desc,r.created_at desc
 ) matching
) a on true left join lateral(
 select u.id,u.name,(select g.name from unit_group_versions g where g.unit_id=u.id and g.valid_from<=f.dt and (g.valid_to is null or g.valid_to>=f.dt) limit 1) grp from unit_versions u
 where u.id::text=a.targets->>'unit' and u.enabled and u.valid_from<=f.dt and (u.valid_to is null or u.valid_to>=f.dt) limit 1
) assigned on true
)
 select case when recipients.id is null then f.fid else f.fid||':share:'||recipients.id::text end,f.dt,f.k,
 case when recipients.id is null then f.amt when recipients.position=recipients.n then f.amt-round(f.amt/recipients.n,2)*(recipients.n-1) else round(f.amt/recipients.n,2) end,
 f.cat,f.proj,case when recipients.id is not null then case when recipients.name ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then recipients.name end when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then null else case when f.raw->>'_humla_allocation_review'='true' then null else f.vrn end end,
 case when recipients.id is not null then recipients.id when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then null else case when f.raw->>'_humla_allocation_review'='true' then null else f.uid end end,
 case when recipients.id is not null then recipients.name when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then null else case when f.raw->>'_humla_allocation_review'='true' then null else f.uname end end,
 case when recipients.id is not null then coalesce(recipients.grp,'Ej klassificerat') when f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') then 'Ej klassificerat' else case when f.raw->>'_humla_allocation_review'='true' then 'Ej klassificerat' else f.grp end end,
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
  where f.k='cost' and f.src='NEXT' and f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','') and coalesce(f.raw->>'_humla_allocation_review','false')<>'true'
  and u.enabled and u.valid_from<=f.dt and (u.valid_to is null or u.valid_to>=f.dt)
  and (f.raw#>>'{_humla_assignment,shared_cost}'='*' or case when left(f.raw#>>'{_humla_assignment,shared_cost}',1)='[' then u.id::text in(select value from jsonb_array_elements_text((f.raw#>>'{_humla_assignment,shared_cost}')::jsonb)) else coalesce(own.name,registry.name)=f.raw#>>'{_humla_assignment,shared_cost}' end)
  order by u.id,u.valid_from desc
 )eligible
 )recipients on true;
end $function$;
CREATE OR REPLACE FUNCTION private.hub_kpi_filtered_source_facts_v1(p_tenant_id uuid, p_from date, p_to date, p_filters jsonb, p_sources text[])
 RETURNS TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb, cost_center text, cost_center_name text, classification_source jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required'; end if;
 return query execute $query$ with facts as materialized(
 select f.fact_id,f.occurred_on,f.kind,f.amount,f.category,f.project,f.vehicle,f.unit_id,f.unit_name,f.business_group,f.source,f.description,f.account,f.file_name,f.row_number,
 case when coalesce(($4->>'_display_projection')::boolean,false) then jsonb_build_object(
 'time_report_id',f.original->'time_report_id','employee_id',f.original->'employee_id',
 'Artikelnummer',f.original->'Artikelnummer','_humla_assignment',f.original->'_humla_assignment',
 '_humla_cost_center',f.original->'_humla_cost_center','_humla_distribution',f.original->'_humla_distribution')
 else f.original end original from private.hub_kpi_financial_source_facts_v1($1,$2,$3,case when $4?'_selected_months' then array(select value::int from jsonb_array_elements_text($4->'_selected_months')) else null end,$5) f
 where (not($4?'_selected_months') or extract(month from f.occurred_on)::int in (select value::int from jsonb_array_elements_text($4->'_selected_months')))
 and (not($4?'unit') or coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=$4->>'unit')
 and (not($4?'vehicle') or coalesce(f.vehicle,'unassigned')=$4->>'vehicle')
 and (not($4?'project') or coalesce(f.project,'unassigned')=$4->>'project')
 and (not($4?'category') or f.category=$4->>'category')
 and (not($4?'kind') or f.kind=$4->>'kind')
 and (not($4?'source') or f.source=$4->>'source')
 and (not($4?'date_from') or f.occurred_on>=($4->>'date_from')::date)
 and (not($4?'date_to') or f.occurred_on<=($4->>'date_to')::date)
 ),
 center_names as materialized(select cost_center,min(cost_center_name) name from public.kpi_project_classification_periods where tenant_id=$1 group by cost_center),
 registry as materialized(select * from public.kpi_project_classification_periods where tenant_id=$1 and valid_from<=$3 and (valid_to is null or valid_to>=$2)),
 registry_vehicles as materialized(select r.id,registration from registry r cross join lateral unnest(r.registrations) registration),
 registry_matches as materialized(
 select f.fact_id,r.id,r.cost_center,r.cost_center_name,r.source,r.business_group,case when r.project_reference=f.project then 1 when f.vehicle=any(r.registrations) then 2 else 3 end priority
 from facts f join registry r on r.project_reference=f.project and r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
 union
 select f.fact_id,r.id,r.cost_center,r.cost_center_name,r.source,r.business_group,case when r.project_reference=f.project then 1 when f.vehicle=any(r.registrations) then 2 else 3 end priority
 from facts f join registry_vehicles v on v.registration=f.vehicle join registry r on r.id=v.id and r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
 union
 select f.fact_id,r.id,r.cost_center,r.cost_center_name,r.source,r.business_group,case when r.project_reference=f.project then 1 when f.vehicle=any(r.registrations) then 2 else 3 end priority
 from facts f join registry r on f.source='TransPA' and r.project_reference=f.original->>'employee_id' and r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
 ),
 centers as materialized(select fact_id,count(distinct cost_center) center_count,min(cost_center) code,min(cost_center_name) name,jsonb_agg(distinct source) sources from registry_matches group by fact_id),
 group_priorities as(select fact_id,min(priority) priority from registry_matches where business_group is not null group by fact_id),
 groups as materialized(select r.fact_id,count(distinct r.business_group) group_count,case when count(distinct r.business_group)=1 then min(r.business_group) end group_name from registry_matches r join group_priorities p on p.fact_id=r.fact_id and p.priority=r.priority where r.business_group is not null group by r.fact_id)
 select f.fact_id,f.occurred_on,f.kind,f.amount,f.category,f.project,f.vehicle,f.unit_id,f.unit_name,
  case when f.original#>>'{_humla_distribution,status}' in ('allocated','no_eligible_units') then f.business_group when nullif(f.original#>>'{_humla_assignment,group}','') is not null then f.business_group when own_group.has_group then f.business_group when explicit_group.has_group then f.business_group
   when cc.center_count>1 or bg.group_count>1 then 'Ej klassificerat' else coalesce(bg.group_name,f.business_group) end,
  f.source,f.description,f.account,f.file_name,f.row_number,case when coalesce(($4->>'_display_projection')::boolean,false) then jsonb_build_object('time_report_id',f.original->'time_report_id','_humla_distribution',f.original->'_humla_distribution') else f.original end,
  coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),article.cost_center,nullif(f.original->>'_humla_cost_center',''),case when cc.center_count=1 then cc.code else 'unclassified' end),
  case when coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),nullif(f.original->>'_humla_cost_center','')) is not null then coalesce((select r.name from center_names r where r.cost_center=coalesce(nullif(f.original#>>'{_humla_assignment,cost_center}',''),f.original->>'_humla_cost_center')),f.original->>'_humla_cost_center') when article.cost_center is not null then coalesce((select r.name from center_names r where r.cost_center=article.cost_center),article.cost_center) when cc.center_count=1 then cc.name else 'Ej klassificerat' end,
  jsonb_build_object('registry_sources',cc.sources,'article_rule_id',article.id,'manual_assignment',f.original->'_humla_assignment','reason',case when f.original#>>'{_humla_assignment,cost_center}' is not null then 'manual_dated_assignment' when f.original->>'_humla_cost_center' is not null then 'verified_import_cost_center' when article.cost_center is not null then 'exact_dated_article_rule' when cc.center_count>1 then 'conflicting_cost_centers' when coalesce(cc.center_count,0)=0 then 'missing_cost_center' else 'exact_dated_reference' end)
 from facts f
 -- A verified dated article rule classifies revenue even without a vehicle/project.
 -- Vehicle identity and group matching retain their existing dated rules.
 left join lateral(
  select a.id,nullif(trim(a.cost_center),'') cost_center
  from public.kpi_workify_article_rules a
  where f.source='Workify' and a.tenant_id=$1 and a.enabled
   and a.article_number=coalesce(f.original->>'Artikelnummer','')
   and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)
  order by a.valid_from desc,a.id limit 1
 ) article on true
 left join centers cc on cc.fact_id=f.fact_id
 left join groups bg on bg.fact_id=f.fact_id
 left join lateral(select exists(select 1 from public.kpi_unit_periods p where p.tenant_id=$1 and p.unit_id=f.unit_id and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on) and nullif(p.payload->>'business_group_id','') is not null) has_group) own_group on true
 left join lateral(select exists(select 1 from public.kpi_project_business_groups p where p.tenant_id=$1 and p.project_reference=f.project and p.source='kpi_admin_dated' and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)) has_group) explicit_group on true;$query$ using p_tenant_id,p_from,p_to,p_filters,p_sources;
end
$function$;
revoke all on function private.hub_kpi_financial_source_facts_v1(uuid,date,date,integer[],text[]) from public,anon,authenticated;
revoke all on function private.hub_kpi_filtered_source_facts_v1(uuid,date,date,jsonb,text[]) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.hub_payment_outcome_source_v1(p_tenant_id uuid, p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare generation uuid;synced timestamptz;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'Not authorized' using errcode='42501';end if;
 if p_as_of is null or p_as_of<'2000-01-01' or p_as_of>'2100-12-31' then raise exception 'Invalid date';end if;
 select active_generation,synced_at into generation,synced from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 select greatest(coalesce(max(coalesce(completed_at,created_at)),synced),(select max(uploaded_at) from private.hub_stena_files_v1 where tenant_id=p_tenant_id and complete)) into synced
 from public.kpi_import_batches where tenant_id=p_tenant_id and data_kind in ('revenue','cost') and completed_at is not null;
 with recursive facts as materialized(
 select * from private.hub_kpi_filtered_source_facts_v1(p_tenant_id,p_as_of-730,p_as_of+90,'{}'::jsonb,array['Workify','NEXT'])
),
 stena_current as materialized(
 select distinct on(r.revenue_object_id) r.revenue_object_id,r.booking,r.occurred_on,
 coalesce(o.amount,r.amount) amount,f.source_kind,f.uploaded_at
 from private.hub_stena_rows_v1 r join private.hub_stena_files_v1 f using(tenant_id,file_hash)
 left join private.hub_stena_amount_overrides_v1 o on o.tenant_id=r.tenant_id and o.revenue_object_id=r.revenue_object_id
 where r.tenant_id=p_tenant_id and f.complete
 and exists(select 1 from private.hub_stena_rules_v1 cfg where cfg.tenant_id=p_tenant_id and cfg.enabled)
 order by r.revenue_object_id,(f.source_kind='settled')desc,f.uploaded_at desc,f.file_hash
),stena_edges as materialized(
 select f.fact_id,s.revenue_object_id from facts f
 cross join lateral regexp_matches(coalesce(f.original->>'Littranummer','')||' '||coalesce(f.original->>'ArtikelKommentar',''),'(?<![0-9])[0-9]{8}(?![0-9])','g') k
 join stena_current s on s.booking=k[1]
 where f.source='Workify' and f.kind='revenue'
 and f.original->>'Kundnamn' in('Elleholms Maskin (STENA)','Stena Recycling AB')
 and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
),stena_blocked(id) as(
 select revenue_object_id from stena_current where amount is null
 union
 select e2.revenue_object_id from stena_blocked b join stena_edges e1 on e1.revenue_object_id=b.id join stena_edges e2 on e2.fact_id=e1.fact_id
),stena_replaced as(
 select distinct e.fact_id from stena_edges e where not exists(
 select 1 from stena_edges x join stena_blocked b on b.id=x.revenue_object_id where x.fact_id=e.fact_id)
),stena_portal as materialized(
 select s.* from stena_current s where s.amount is not null and s.occurred_on between p_as_of-730 and p_as_of+90
 and not exists(select 1 from stena_blocked b where b.id=s.revenue_object_id)
),
revenues as(
 select fact_id id,cost_center center,'in'::text kind,occurred_on date,amount,coalesce(original->>'Kundnamn','') party,
 private.hub_kpi_workify_date_v1(coalesce(nullif(trim(original->>'Fakturadatum'),''),nullif(trim(original->>'Fakturerad'),''))) invoice_date,
 (coalesce(original->>'Kundnamn','')~*'^elleholms[[:space:]]+maskin' and regexp_replace(lower(coalesce(original->>'Kundnamn','')),'[^a-zåäö0-9]+','','g')<>'elleholmsmaskinstena') internal,false one_off,null::text row_id,coalesce(original->>'Ordernummer','') reference,description,account,project
 from facts f where source='Workify' and kind='revenue' and not exists(select 1 from stena_replaced x where x.fact_id=f.fact_id)
 union all
 select s.revenue_object_id::text,'30','in',s.occurred_on,s.amount,'Stena Recycling AB',
 null::date,false,false,null::text,s.booking,'Stena transport',null::text,null::text
 from stena_portal s
 ),cost_base as(
 select f.*,case when account='7010' then 'payroll_separate'
 when private.hub_ps_own_tank_source_v1(original,account) then 'own_tank_consumption'
 when coalesce(original->>'Verifikation nr','')~'^(AO[.]|ARB[.]|NEXT[.](AO|ARB))' then 'internal_time_or_allocation'
 else null end exclusion_reason
 from facts f where source='NEXT' and kind='cost'
 ),costs as(
 select fact_id id,cost_center center,'out'::text kind,occurred_on date,
 coalesce((original#>>'{_humla_fuel_reconciliation,booked_amount}')::numeric,amount) amount,
 coalesce(nullif(trim(original->>'Leverantör'),''),'') party,null::date invoice_date,
 coalesce(original->>'Leverantör','')~*'^elleholms[[:space:]]+maskin' internal,
 exists(select 1 from private.hub_payment_forecast_exclusions e where e.tenant_id=p_tenant_id and e.row_id::text=split_part(fact_id,':',1) and e.excluded) one_off,
 split_part(fact_id,':',1) row_id,coalesce(original->>'Verifikationstext',description,'') reference,description,account,project
 from cost_base where exclusion_reason is null
 ),daily as(
 select * from revenues union all select * from costs
 ), exclusions as(
 select exclusion_reason reason,count(*)rows,round(sum(coalesce((original#>>'{_humla_fuel_reconciliation,booked_amount}')::numeric,amount)),2)amount from cost_base where exclusion_reason is not null group by 1
 )
 select jsonb_build_object('synced_at',synced,'generation',generation,
 'rows',coalesce((select jsonb_agg(jsonb_build_object('center',daily.center,'kind',daily.kind,'date',daily.date,'amount',daily.amount,'party',party,'invoiceDate',invoice_date,'internal',internal,'oneOff',one_off,'id',id,'rowId',row_id,'reference',reference,'description',description,'account',account,'project',project,'source',case when sp.revenue_object_id is not null then 'Stena portal' when kind='in' then 'Workify' else 'NEXT' end,'amountStatus',sp.source_kind)order by daily.date,daily.center,daily.kind,party,id)from daily left join stena_portal sp on sp.revenue_object_id::text=daily.id),'[]'::jsonb),
 'review_rows',0,'review_amount',0,
 'controls',jsonb_build_object('scope','live_approved_imports','from',p_as_of-730,'to',p_as_of+90,
 'supplierRows',(select count(*)from costs),'supplierAmount',(select coalesce(sum(amount),0)from costs),
 'excludedNonPayments',coalesce((select jsonb_agg(to_jsonb(e)order by reason)from exclusions e),'[]'::jsonb),
 'stena',jsonb_build_object('rows',(select count(*)from stena_portal),
 'settledRows',(select count(*)from stena_portal where source_kind='settled'),
 'settledAmount',(select coalesce(sum(amount),0)from stena_portal where source_kind='settled'),
 'historyRows',(select count(*)from stena_portal where source_kind='history'),
 'historyAmount',(select coalesce(sum(amount),0)from stena_portal where source_kind='history'),
 'unresolvedRows',(select count(*)from stena_current s where s.occurred_on between p_as_of-730 and p_as_of+90 and exists(select 1 from stena_blocked b where b.id=s.revenue_object_id)),
 'replacedWorkifyRows',(select count(*)from stena_replaced)),
 'originalsPreserved',true,'noLiveImportAmounts',false,'latestUploadedSource',true))into answer;
 return answer;
end $function$;


