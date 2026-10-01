-- Initial setup is a draft; locked compositions retain their dated history.
create table public.kpi_unit_initial_setup (
 unit_id uuid primary key references public.kpi_units(id),
 tenant_id uuid not null references public.hub_tenants(id),
 locked_at timestamptz,
 locked_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);
alter table public.kpi_unit_initial_setup enable row level security;
revoke all on public.kpi_unit_initial_setup from anon,authenticated;
grant select on public.kpi_unit_initial_setup to authenticated;
create policy kpi_unit_initial_setup_read on public.kpi_unit_initial_setup for select to authenticated
 using (public.hub_has_permission(tenant_id,'kpi.manage'));

create table public.kpi_unit_initial_setup_events (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.hub_tenants(id),
 unit_id uuid not null references public.kpi_units(id),
 actor uuid not null references auth.users(id),
 action text not null check(action in ('create_initial','correct_initial','lock_initial')),
 previous_periods jsonb not null default '[]',
 next_payload jsonb not null,
 created_at timestamptz not null default now()
);
create index kpi_unit_initial_setup_events_tenant_unit on public.kpi_unit_initial_setup_events(tenant_id,unit_id,created_at);
alter table public.kpi_unit_initial_setup_events enable row level security;
revoke all on public.kpi_unit_initial_setup_events from anon,authenticated;
grant select on public.kpi_unit_initial_setup_events to authenticated;
create policy kpi_unit_initial_setup_events_read on public.kpi_unit_initial_setup_events for select to authenticated
 using (public.hub_has_permission(tenant_id,'kpi.manage'));

-- Only the unconfirmed, single-period equipment drafts imported in this build are opened.
-- Existing multi-period units and every other existing unit remain locked.
insert into public.kpi_unit_initial_setup(unit_id,tenant_id)
 select u.id,u.tenant_id from public.kpi_units u
 join public.kpi_unit_periods p on p.unit_id=u.id and p.tenant_id=u.tenant_id
 where u.origin in ('manual','manual_builder')
 and p.payload->'source'->>'type'='user_verified_fordonskontrollen_screenshot'
 and p.payload->'source'->>'file'='image(20261001-061808).png'
 and p.valid_from='2026-10-01'
 and (select count(*) from public.kpi_unit_periods h where h.unit_id=u.id)=1;

create or replace function public.hub_kpi_save_unit_v2(
 p_tenant_id uuid,p_payload jsonb,p_unit_id uuid default null,p_revision integer default null
) returns uuid language plpgsql security definer set search_path='' as $function$
declare
 uid uuid; old public.kpi_units; effective date; ending date; latest date;
 today date := (now() at time zone 'Europe/Stockholm')::date;
 initial boolean := coalesce((p_payload->>'initial_setup')::boolean,false);
 finalize boolean := coalesce((p_payload->>'finalize_setup')::boolean,false);
 is_open boolean; period_count integer; previous_periods jsonb; last_payload jsonb;
 group_id uuid;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then
  raise exception 'KPI-administratör krävs';
 end if;
 if p_unit_id is not null then
  select * into old from public.kpi_units where id=p_unit_id and tenant_id=p_tenant_id for update;
  if not found or old.revision is distinct from p_revision then raise exception 'Enheten har ändrats. Ladda om innan du sparar';end if;
  select count(*),max(valid_from),coalesce(jsonb_agg(to_jsonb(p) order by valid_from),'[]')
   into period_count,latest,previous_periods from public.kpi_unit_periods p where p.unit_id=old.id and p.tenant_id=p_tenant_id;
  select payload into last_payload from public.kpi_unit_periods where unit_id=old.id and tenant_id=p_tenant_id order by valid_from desc limit 1;
  -- Preserve provenance and omitted optional fields; explicit null removes an own group.
  p_payload:=coalesce(last_payload,'{}')||p_payload;
  select locked_at is null into is_open from public.kpi_unit_initial_setup where unit_id=old.id and tenant_id=p_tenant_id;
  is_open:=coalesce(is_open,false);
  if initial and (not is_open or period_count<>1) then raise exception 'Grundkopplingen är låst. Historiken får inte skrivas om';end if;
 end if;
 if p_payload->>'unit_type' in ('vehicle','compound') and jsonb_array_length(p_payload->'registrations')>0 then
  if nullif(trim(p_payload->>'main_vehicle'),'') is null and jsonb_array_length(p_payload->'registrations')=1 then
   p_payload:=jsonb_set(p_payload,'{main_vehicle}',p_payload->'registrations'->0);
  end if;
  if nullif(trim(p_payload->>'main_vehicle'),'') is null or not (p_payload->'registrations' @> jsonb_build_array(p_payload->>'main_vehicle')) then
   raise exception 'Välj intäktsbärande huvudfordon bland enhetens regnummer';
  end if;
  p_payload:=jsonb_set(p_payload,'{name}',to_jsonb(p_payload->>'main_vehicle'));
 end if;
 effective:=(p_payload->>'valid_from')::date;ending:=nullif(p_payload->>'valid_to','')::date;
 if effective is null or (ending is not null and ending<effective)
  or coalesce(length(trim(p_payload->>'name')),0) not between 1 and 120
  or coalesce(p_payload->>'unit_type','') not in ('vehicle','person','overhead','compound') then raise exception 'Ogiltiga enhetsuppgifter';end if;
 if jsonb_typeof(p_payload->'projects') is distinct from 'array'
  or jsonb_typeof(p_payload->'registrations') is distinct from 'array'
  or jsonb_typeof(p_payload->'employees') is distinct from 'array' then raise exception 'Ogiltiga referenslistor';end if;
 if jsonb_array_length(p_payload->'projects')+jsonb_array_length(p_payload->'registrations')+jsonb_array_length(p_payload->'employees') not between 1 and 300 then raise exception 'Ange 1–300 referenser';end if;
 if exists(select 1 from jsonb_array_elements_text(p_payload->'registrations') r where r !~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$') then raise exception 'Ogiltigt regnummer';end if;
 group_id:=nullif(p_payload->>'business_group_id','')::uuid;
 if group_id is not null and not exists(select 1 from public.kpi_business_groups where id=group_id and tenant_id=p_tenant_id and enabled) then raise exception 'Välj en aktiv verksamhetsgrupp i samma arbetsyta';end if;
 p_payload:=p_payload-'initial_setup'-'finalize_setup';
 if p_unit_id is null then
  insert into public.kpi_units(tenant_id,name,unit_type,projects,registrations,employees,valid_from,valid_to,enabled,origin)
  values(p_tenant_id,trim(p_payload->>'name'),p_payload->>'unit_type',
   array(select jsonb_array_elements_text(p_payload->'projects')),array(select jsonb_array_elements_text(p_payload->'registrations')),
   array(select jsonb_array_elements_text(p_payload->'employees')),effective,ending,coalesce((p_payload->>'enabled')::boolean,true),'manual') returning id into uid;
  insert into public.kpi_unit_initial_setup(unit_id,tenant_id,locked_at,locked_by)
   values(uid,p_tenant_id,case when finalize then now() end,case when finalize then auth.uid() end);
  insert into public.kpi_unit_initial_setup_events(tenant_id,unit_id,actor,action,next_payload)
   values(p_tenant_id,uid,auth.uid(),'create_initial',p_payload);
 else
  uid:=old.id;
  if initial then
   -- Archive the complete draft before correcting it. Locked history never enters this branch.
   insert into public.kpi_unit_initial_setup_events(tenant_id,unit_id,actor,action,previous_periods,next_payload)
    values(p_tenant_id,uid,auth.uid(),case when finalize then 'lock_initial' else 'correct_initial' end,previous_periods,p_payload);
   delete from public.kpi_unit_periods where unit_id=uid and tenant_id=p_tenant_id;
  else
   if effective<today then raise exception 'Efter grundkopplingen får ändringar inte bakåtdateras. Välj idag eller senare';end if;
   if effective<=coalesce(latest,old.valid_from) then raise exception 'Ny koppling måste börja efter senaste periodens start';end if;
   if latest is null then
    insert into public.kpi_unit_periods(tenant_id,unit_id,valid_from,valid_to,payload,created_by)
    values(p_tenant_id,uid,old.valid_from,least(effective-1,coalesce(old.valid_to,effective-1)),to_jsonb(old),auth.uid());
   else
    update public.kpi_unit_periods set valid_to=effective-1 where unit_id=uid and valid_from=latest and (valid_to is null or valid_to>=effective);
   end if;
   if is_open then
    insert into public.kpi_unit_initial_setup_events(tenant_id,unit_id,actor,action,previous_periods,next_payload)
     values(p_tenant_id,uid,auth.uid(),'lock_initial',previous_periods,p_payload);
   end if;
  end if;
  if (initial and finalize) or not initial then
   update public.kpi_unit_initial_setup set locked_at=coalesce(locked_at,now()),locked_by=coalesce(locked_by,auth.uid())
    where unit_id=uid and tenant_id=p_tenant_id;
  end if;
  update public.kpi_units set name=trim(p_payload->>'name'),unit_type=p_payload->>'unit_type',
   projects=array(select jsonb_array_elements_text(p_payload->'projects')),
   registrations=array(select jsonb_array_elements_text(p_payload->'registrations')),
   employees=array(select jsonb_array_elements_text(p_payload->'employees')),enabled=coalesce((p_payload->>'enabled')::boolean,true),
   valid_from=case when initial then effective else valid_from end,
   valid_to=case when initial then ending else valid_to end
   where id=uid;
 end if;
 insert into public.kpi_unit_periods(tenant_id,unit_id,valid_from,valid_to,payload,created_by)
  values(p_tenant_id,uid,effective,ending,p_payload,auth.uid());
 return uid;
end $function$;


-- An explicit dated unit group covers every uniquely resolved fact in that unit.
create or replace function private.hub_kpi_financial_facts_v1(p_tenant_id uuid,p_from date,p_to date)
returns table(fact_id text,occurred_on date,kind text,amount numeric,category text,project text,vehicle text,unit_id uuid,unit_name text,business_group text,source text,description text,account text,file_name text,row_number integer,original jsonb)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 then raise exception 'Invalid period'; end if;
 return query
 with unit_versions as materialized (
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
 ) select f.fid,f.dt,f.k,f.amt,f.cat,f.proj,f.vrn,f.uid,f.uname,f.grp,f.src,f.descr,f.acc,f.fn,f.rn,f.raw from related f;
end $$;
revoke all on function private.hub_kpi_financial_facts_v1(uuid,date,date) from public,anon;
grant execute on function private.hub_kpi_financial_facts_v1(uuid,date,date) to authenticated;

