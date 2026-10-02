CREATE OR REPLACE FUNCTION public.hub_kpi_match_queue_v2(p_tenant_id uuid, p_from date, p_to date, p_dimension text DEFAULT 'cost_center'::text, p_reference_type text DEFAULT 'project'::text, p_search text DEFAULT ''::text, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
AS $function$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_dimension not in ('all','cost_center','group','unit','vehicle','category','shared_cost') or p_reference_type not in ('project','vehicle','article','account','fact') or p_from is null or p_to<p_from or p_to-p_from>366 or p_page<0 then raise exception 'Ogiltigt urval';end if;
 with facts as materialized(select * from private.hub_kpi_classified_facts_v1(p_tenant_id,p_from,p_to)),
 rows as(
  select fact_id,occurred_on,kind,amount,project,vehicle,account,original,source,description,file_name,row_number,cost_center,business_group,unit_id::text unit_key,unit_name,category,false held from facts where case p_dimension when 'all' then true when 'cost_center' then cost_center='unclassified' when 'group' then business_group='Ej klassificerat' when 'unit' then unit_id is null when 'vehicle' then vehicle is null when 'shared_cost' then source='NEXT' and kind='cost' and project is not null else category in ('other','unclassified') end
  union all select r.id::text,r.occurred_on,r.data_kind,r.amount,r.project_reference,r.vehicle_registration,r.account,r.source_data,case when r.data_kind='cost' then 'NEXT' else 'Workify' end,r.description,(select b.file_name from public.kpi_import_batches b where b.id=r.batch_id and b.tenant_id=p_tenant_id),r.row_number,'unclassified','Ej klassificerat',null::text,null::text,'unclassified',true
  from public.kpi_import_rows r where r.tenant_id=p_tenant_id and not r.is_valid and r.data_kind in ('cost','revenue') and r.occurred_on between p_from and p_to and (p_dimension<>'shared_cost' or (r.data_kind='cost' and r.project_reference is not null))
 ), keyed as(select rows.*,named.project_name,named.registrations register_vehicles,case p_reference_type when 'project' then case when original?'_humla_original_project' then original->>'_humla_original_project' else project end when 'vehicle' then coalesce(original->>'_humla_original_registration',vehicle) when 'article' then nullif(original->>'Artikelnummer','') when 'account' then account else fact_id end reference from rows left join lateral(select r.project_name,r.registrations from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and r.project_reference=rows.project and r.valid_from<=rows.occurred_on and (r.valid_to is null or r.valid_to>=rows.occurred_on) order by r.valid_from desc,r.id limit 1)named on true),
 grouped as(select source,kind,coalesce(reference,fact_id) reference,case when reference is null then 'fact' else p_reference_type end reference_type,min(description) description,min(project_name) project_name,
coalesce(jsonb_agg(distinct vehicle)filter(where nullif(vehicle,'') is not null),'[]') vehicles,
coalesce(jsonb_agg(distinct to_jsonb(register_vehicles))filter(where register_vehicles is not null),'[]') register_vehicles,
coalesce(jsonb_agg(distinct jsonb_build_object('reference',project,'name',project_name))filter(where project is not null),'[]') projects,
coalesce(jsonb_agg(distinct account)filter(where account is not null),'[]') accounts,
coalesce(jsonb_agg(distinct original->>'Leverantör')filter(where original->>'Leverantör' is not null),'[]') suppliers,
coalesce(jsonb_agg(distinct cost_center),'[]') current_cost_centers,coalesce(jsonb_agg(distinct business_group),'[]') current_groups,coalesce(jsonb_agg(distinct unit_name)filter(where unit_name is not null),'[]') current_units,coalesce(jsonb_agg(distinct category),'[]') current_categories,bool_or(held) held,
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
revoke all on function public.hub_kpi_match_queue_v2(uuid,date,date,text,text,text,integer) from public,anon;
grant execute on function public.hub_kpi_match_queue_v2(uuid,date,date,text,text,text,integer) to authenticated;
CREATE OR REPLACE FUNCTION public.hub_kpi_match_save_v1(p_tenant_id uuid, p_items jsonb, p_dimension text, p_target text, p_from date, p_to date, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item jsonb; ref text; typ text; src text; k text; affected integer:=0; result_id uuid;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_dimension is null or p_dimension not in ('cost_center','group','unit','vehicle','project','category','shared_cost') or nullif(trim(p_target),'') is null or p_from is null or (p_to is not null and p_to<p_from) or length(trim(coalesce(p_reason,''))) not between 3 and 1000 or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Kontrollera urval, giltighetsdatum och motivering';end if;
 if p_dimension='shared_cost' and left(p_target,1)='[' then
  if jsonb_typeof(p_target::jsonb)<>'array' or jsonb_array_length(p_target::jsonb) not between 1 and 100 or exists(select 1 from jsonb_array_elements_text(p_target::jsonb) v where not exists(select 1 from public.kpi_units u where u.tenant_id=p_tenant_id and u.id::text=v.value and u.enabled and u.origin in ('manual','manual_builder'))) then raise exception 'Välj giltiga ekonomiska enheter för fördelning';end if;
 end if;
 if p_dimension='shared_cost' and left(p_target,1)<>'[' and p_target not in ('*','none') and not exists(select 1 from public.kpi_business_groups where tenant_id=p_tenant_id and enabled and name=p_target) then raise exception 'Välj alla enheter eller en giltig verksamhetsgrupp';end if;
 if p_dimension='cost_center' and not exists(select 1 from public.kpi_project_classification_periods where tenant_id=p_tenant_id and cost_center=p_target) then raise exception 'Okänt kostnadsställe';end if;
 if p_dimension='group' and not exists(select 1 from public.kpi_business_groups where tenant_id=p_tenant_id and enabled and name=p_target) then raise exception 'Okänd verksamhetsgrupp';end if;
 if p_dimension='unit' and not exists(select 1 from public.kpi_units where tenant_id=p_tenant_id and id::text=p_target and origin in ('manual','manual_builder') and enabled) then raise exception 'Okänd ekonomisk enhet';end if;
 if p_dimension='vehicle' and p_target !~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then raise exception 'Ange verifierat registreringsnummer';end if;
 if p_dimension='project' and not exists(select 1 from public.kpi_units u where u.tenant_id=p_tenant_id and p_target=any(u.projects) union all select 1 from public.kpi_project_classification_periods r where r.tenant_id=p_tenant_id and r.project_reference=p_target) then raise exception 'Välj ett registrerat projekt i samma arbetsyta';end if;
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
  if src='NEXT' and p_dimension in ('cost_center','unit','vehicle','project','group','shared_cost') then
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
end $function$
;
CREATE OR REPLACE FUNCTION private.hub_kpi_financial_facts_v1(p_tenant_id uuid, p_from date, p_to date)
 RETURNS TABLE(fact_id text, occurred_on date, kind text, amount numeric, category text, project text, vehicle text, unit_id uuid, unit_name text, business_group text, source text, description text, account text, file_name text, row_number integer, original jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
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
 ), routed as (
  select f.fid,f.dt,f.k,f.amt,f.cat,coalesce(a.target,f.proj) proj,coalesce(v.target,f.reg) reg,f.src,f.descr,f.acc,f.fn,f.rn,
   f.raw||case when a.target is not null then jsonb_build_object('_humla_original_project',f.proj,'_humla_project_assignment',a.target) else '{}'::jsonb end||case when v.target is not null then jsonb_build_object('_humla_original_registration',f.reg,'_humla_vehicle_assignment',v.target) else '{}'::jsonb end raw
  from raw_facts f left join lateral(
   select r.target from allocation_rules r
   where r.dimension='project' and r.source=f.src and r.kind=f.k and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt)
   and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=f.proj when 'vehicle' then r.reference=coalesce(nullif(f.reg,''),(select case when count(distinct upper(trim(pm.vehicle_registration)))=1 then max(upper(trim(pm.vehicle_registration))) end from (select project_reference,vehicle_registration,valid_from,valid_to,true enabled,tenant_id from public.kpi_project_vehicle_periods where tenant_id=p_tenant_id union all select project_reference,vehicle_registration,valid_from,valid_to,enabled,tenant_id from public.kpi_project_unit_mappings legacy where tenant_id=p_tenant_id and not exists(select 1 from public.kpi_project_vehicle_periods h where h.tenant_id=p_tenant_id and h.project_reference=legacy.project_reference)) pm where pm.enabled and pm.project_reference=f.proj and f.dt>=coalesce(pm.valid_from,'2000-01-01') and (pm.valid_to is null or f.dt<=pm.valid_to))) when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc else false end
   order by case r.reference_type when 'fact' then 1 when 'project' then 2 when 'vehicle' then 3 when 'article' then 4 else 5 end,r.valid_from desc,r.created_at desc limit 1
  ) a on true
  left join lateral(
   select r.target from allocation_rules r
   where r.dimension='vehicle' and r.source=f.src and r.kind=f.k and r.valid_from<=f.dt and (r.valid_to is null or r.valid_to>=f.dt)
   and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=f.proj when 'vehicle' then r.reference=f.reg when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc else false end
   order by case r.reference_type when 'fact' then 1 when 'project' then 2 when 'vehicle' then 3 when 'article' then 4 else 5 end,r.valid_from desc,r.created_at desc limit 1
  ) v on true
 ), mapped as (
  select f.*,case when f.k='cost' and f.raw->>'_humla_include_in_vehicle_result'='false' then null when f.proj='9009' or f.reg='LASTBIL' then 'LASTBIL' else coalesce(nullif(f.reg,''),m.reg) end vrn
  from routed f left join lateral (
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
 and case r.reference_type when 'fact' then r.reference=f.fid when 'project' then r.reference=case when f.raw?'_humla_original_project' then f.raw->>'_humla_original_project' else f.proj end when 'vehicle' then (r.reference=f.vrn or r.reference=f.raw->>'_humla_original_registration') when 'article' then r.reference=f.raw->>'Artikelnummer' when 'account' then r.reference=f.acc else false end
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
  and (f.raw#>>'{_humla_assignment,shared_cost}'='*' or case when left(f.raw#>>'{_humla_assignment,shared_cost}',1)='[' then u.id::text in(select value from jsonb_array_elements_text((f.raw#>>'{_humla_assignment,shared_cost}')::jsonb)) else coalesce(own.name,registry.name)=f.raw#>>'{_humla_assignment,shared_cost}' end)
  order by u.id,u.valid_from desc
 )eligible
 )recipients on true;
end $function$
;
create or replace function public.hub_kpi_match_changes_v1(p_tenant_id uuid,p_changes jsonb,p_from date,p_to date,p_reason text,p_preview boolean default true)
returns jsonb language plpgsql security invoker set search_path='' set statement_timeout='60s' as $fn$
declare change jsonb; output jsonb; before_values jsonb; after_values jsonb; result jsonb; saved integer:=0;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'array' or jsonb_array_length(p_changes) not between 1 and 100 or p_from is null or p_to<p_from or p_to-p_from>366 then raise exception 'Kontrollera urval och datum';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':kpi-matching',0));
 if p_preview then
  with facts as materialized(select * from private.hub_kpi_classified_facts_v1(p_tenant_id,p_from,p_to)), cc as(select cost_center,sum(amount) filter(where kind='cost') cost,sum(amount) filter(where kind='revenue') revenue from facts group by cost_center), units as(select coalesce(unit_name,'Ej fördelat') name,sum(amount) filter(where kind='cost') cost,sum(amount) filter(where kind='revenue') revenue from facts group by 1)
  select jsonb_build_object('cost_centers',(select jsonb_agg(to_jsonb(c)) from cc c),'units',(select jsonb_agg(to_jsonb(u)) from units u),'cost',(select coalesce(sum(amount)filter(where kind='cost'),0)from facts),'revenue',(select coalesce(sum(amount)filter(where kind='revenue'),0)from facts)) into before_values;
 end if;
 begin
  for change in select value from jsonb_array_elements(p_changes) loop
   result:=public.hub_kpi_match_save_many_v1(p_tenant_id,jsonb_build_array(change->'item'),change->'targets',(change->>'valid_from')::date,nullif(change->>'valid_to','')::date,p_reason);
   saved:=saved+(result->>'saved')::int;
  end loop;
  if p_preview then
   with facts as materialized(select * from private.hub_kpi_classified_facts_v1(p_tenant_id,p_from,p_to)), cc as(select cost_center,sum(amount) filter(where kind='cost') cost,sum(amount) filter(where kind='revenue') revenue from facts group by cost_center), units as(select coalesce(unit_name,'Ej fördelat') name,sum(amount) filter(where kind='cost') cost,sum(amount) filter(where kind='revenue') revenue from facts group by 1)
   select jsonb_build_object('cost_centers',(select jsonb_agg(to_jsonb(c)) from cc c),'units',(select jsonb_agg(to_jsonb(u)) from units u),'cost',(select coalesce(sum(amount)filter(where kind='cost'),0)from facts),'revenue',(select coalesce(sum(amount)filter(where kind='revenue'),0)from facts)) into after_values;
   output:=jsonb_build_object('before',before_values,'after',after_values,'saved',saved,'preview',true);
   raise exception using errcode='PZ001',message='preview_rollback';
  end if;
 exception when sqlstate 'PZ001' then
  if not p_preview then raise;end if;
 end;
 return coalesce(output,jsonb_build_object('saved',saved,'preview',false));
end $fn$;
revoke all on function public.hub_kpi_match_changes_v1(uuid,jsonb,date,date,text,boolean) from public,anon;
grant execute on function public.hub_kpi_match_changes_v1(uuid,jsonb,date,date,text,boolean) to authenticated;
