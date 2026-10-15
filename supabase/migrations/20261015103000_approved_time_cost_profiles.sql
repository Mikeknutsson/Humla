-- Approved, bounded estimates. Raw time and accounting imports remain immutable.
create table private.hub_time_cost_profiles(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,batch_id uuid not null references public.kpi_import_batches(id),
 kind text not null check(kind in('historical_payroll','missing_workshop_debit')),
 period_from date not null,period_to date not null,cost_centers text[] not null,
 monthly_salary numeric not null check(monthly_salary>0),weekly_hours numeric not null check(weekly_hours>0),
 overtime_multiplier numeric not null check(overtime_multiplier>=1),load_factor numeric not null check(load_factor>=1),
 approval_reference text not null,approved_by uuid not null,approved_at timestamptz not null default now(),enabled boolean not null default true,
 unique(tenant_id,batch_id,kind,period_from,period_to),check(period_to>=period_from)
);
alter table private.hub_time_cost_profiles enable row level security;
revoke all on private.hub_time_cost_profiles from public,anon,authenticated;
create table private.hub_time_cost_publications(
 tenant_id uuid not null,generation_id uuid not null references private.hub_kpi_report_generations(id)on delete cascade,
 profile_id uuid not null references private.hub_time_cost_profiles(id),summary jsonb not null,created_by uuid not null,created_at timestamptz not null default now(),
 primary key(generation_id,profile_id)
);
alter table private.hub_time_cost_publications enable row level security;
revoke all on private.hub_time_cost_publications from public,anon,authenticated;

create function private.hub_approved_time_cost_basis_v1(p_tenant uuid,p_generation uuid)
returns table(profile_id uuid,batch_id uuid,row_id uuid,row_number integer,person_id uuid,work_date date,project text,cost_center text,
 role text,hours numeric,covered_hours numeric,gap_hours numeric,regular_hours numeric,overtime_hours numeric,cost numeric,profile_kind text)
language plpgsql stable set search_path='' set jit='off' as $$
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant,'kpi.read')then raise exception 'KPI read required'using errcode='42501';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where tenant_id=p_tenant and id=p_generation)then raise exception 'Generation mismatch';end if;
 return query
 with keys as materialized(
  select identity_type,identity_value,(array_agg(distinct object_id))[1]person_id from public.hub_identity_keys
  where tenant_id=p_tenant and object_type='Person'and identity_type in('next_person_name','transpa_employee_id')and confidence=1
  group by 1,2 having count(distinct object_id)=1
 ), native as materialized(
  select coalesce(t.person_object_id,k.person_id)person_id,t.work_date,sum(t.work_hours)hours
  from private.hub_kpi_prepared_kpi_transpa_time_facts t left join keys k on k.identity_type='transpa_employee_id'and k.identity_value=t.employee_id
  where t.tenant_id=p_tenant and t.generation_id=p_generation and t.work_hours>0 group by 1,2
 ), src0 as materialized(
  select p.id profile_id,r.batch_id,r.id row_id,r.row_number,coalesce(r.employee_object_id,k.person_id)person_id,
   r.occurred_on work_date,r.project_reference project,
   coalesce(nullif(r.cost_center,''),nullif(r.source_data->>'Kostnadsställe nr',''),'unclassified')cost_center,
   upper(coalesce(nullif(r.source_data->>'Roll',''),r.description,''))role,upper(trim(coalesce(r.source_data->>'Tidkod','')))code,
   r.paid_hours hours,p.kind,p.monthly_salary,p.weekly_hours,p.overtime_multiplier,p.load_factor,
   (r.source_data-array['Godkänd','Godkänd av','Godkännandedatum','Fakturadatum','_humla_time_approval'])fingerprint,
   r.created_at
  from private.hub_kpi_prepared_kpi_import_rows r join private.hub_time_cost_profiles p on p.tenant_id=r.tenant_id and p.batch_id=r.batch_id and p.enabled
  join public.kpi_import_batches b on b.tenant_id=r.tenant_id and b.id=r.batch_id and b.status='completed'
  left join keys k on k.identity_type='next_person_name'and k.identity_value=upper(trim(coalesce(r.employee_number,r.source_data->>'Namn')))
  where r.tenant_id=p_tenant and r.generation_id=p_generation and r.data_kind='next_historical_time'and r.is_valid and r.paid_hours>0
   and r.occurred_on between p.period_from and p.period_to
   and(lower(coalesce(r.source_data->>'Godkänd',''))in('true','1','ja')or r.source_data#>>'{_humla_time_approval,approved}'='true')
   and coalesce(r.project_reference,'')<>'99999'and coalesce(lower(trim(r.source_data->>'Projektnamn')),'')<>'frånvaro'
   and upper(trim(coalesce(r.source_data->>'Tidkod','')))!~'^OB'
 ), numbered as(
  select s.*,row_number()over(partition by s.batch_id,s.fingerprint order by s.row_number,s.row_id)occurrence from src0 s
 ), deduped as(
  select s.*,row_number()over(partition by s.kind,s.fingerprint,s.occurrence order by s.created_at desc,s.row_id)copy_rank from numbered s
 ), scoped as materialized(
  select s.* from deduped s join private.hub_time_cost_profiles p on p.id=s.profile_id
  where copy_rank=1 and s.cost_center=any(p.cost_centers)
   and(s.kind='historical_payroll'or(s.role='REP'and not exists(
    select 1 from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation and f.source='NEXT'
     and f.kind='cost'and f.account='4630'and f.amount<>0 and f.project=s.project and f.cost_center=s.cost_center
     and date_trunc('month',f.occurred_on)=date_trunc('month',s.work_date)
     and(concat_ws(' ',f.description,f.original->>'Verifikationstext')ilike '%verkstad%'or f.original->>'Verifikation nr'~'^AO[.][0-9]{4}-[0-9]{2}$')
   )))
 ), days as(
  select s.profile_id,s.person_id,s.work_date,sum(s.hours)hours from scoped s group by 1,2,3
 ), gaps as materialized(
  select s.*,case when s.kind='historical_payroll'then least(coalesce(n.hours,0),d.hours)*s.hours/d.hours else 0 end covered,
   case when s.kind='historical_payroll'then greatest(d.hours-coalesce(n.hours,0),0)*s.hours/d.hours else s.hours end gap,
   date_trunc('week',s.work_date)::date week_start,s.code~'^(ÖT|ÖK)'explicit_ot
  from scoped s join days d on d.profile_id=s.profile_id and d.person_id is not distinct from s.person_id and d.work_date=s.work_date
  left join native n on n.person_id=s.person_id and n.work_date=s.work_date
 ), weeks as(
  select s.profile_id,s.person_id,s.week_start,sum(s.gap)filter(where not s.explicit_ot)normal_gap,max(s.weekly_hours)capacity,
   (select coalesce(sum(n.hours),0)from native n where n.person_id=s.person_id and n.work_date>=s.week_start and n.work_date<s.week_start+7)native_hours
  from gaps s group by 1,2,3
 ), costed as(
  select s.*,case when s.explicit_ot then s.gap else s.gap*least(1,(greatest(w.native_hours+coalesce(w.normal_gap,0)-w.capacity,0)-greatest(w.native_hours-w.capacity,0))/nullif(w.normal_gap,0))end ot_gap
  from gaps s join weeks w on w.profile_id=s.profile_id and w.person_id is not distinct from s.person_id and w.week_start=s.week_start
 )select s.profile_id,s.batch_id,s.row_id,s.row_number,s.person_id,s.work_date,s.project,s.cost_center,s.role,s.hours,s.covered,s.gap,
  s.gap-coalesce(s.ot_gap,0),coalesce(s.ot_gap,0),
  round((s.gap-coalesce(s.ot_gap,0)+coalesce(s.ot_gap,0)*s.overtime_multiplier)*s.monthly_salary/(s.weekly_hours*52/12)*s.load_factor,2),s.kind
 from costed s;
end $$;
revoke all on function private.hub_approved_time_cost_basis_v1(uuid,uuid)from public,anon,authenticated;

create function private.hub_publish_approved_time_costs_v1(p_tenant uuid,p_generation uuid)
returns jsonb language plpgsql set search_path='' set jit='off' set plan_cache_mode='force_custom_plan' as $$
declare n integer;answer jsonb;
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'KPI management required'using errcode='42501';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where tenant_id=p_tenant and id=p_generation)then raise exception 'Generation mismatch';end if;
 perform pg_advisory_xact_lock(hashtextextended('approved-time-costs:'||p_tenant::text,0));
 if not exists(select 1 from private.hub_time_cost_profiles p where p.tenant_id=p_tenant and p.enabled and not exists(
  select 1 from private.hub_time_cost_publications x where x.tenant_id=p_tenant and x.generation_id=p_generation and x.profile_id=p.id))then return jsonb_build_object('published_profiles',0);end if;
 create temporary table _approved_time_basis on commit drop as
 select b.* from private.hub_approved_time_cost_basis_v1(p_tenant,p_generation)b
 where not exists(select 1 from private.hub_time_cost_publications x where x.tenant_id=p_tenant and x.generation_id=p_generation and x.profile_id=b.profile_id);
 if exists(select 1 from pg_temp._approved_time_basis where person_id is null or cost<0 or gap_hours<0 or covered_hours<0 or abs(gap_hours+covered_hours-hours)>0.000001)then raise exception 'Invalid approved time/person/overlap basis';end if;
 -- Reference hours are counted per original transaction, not per allocated recipient.
 create temporary table _approved_time_offsets on commit drop as
 with file_hours as(
  select b.profile_id,b.project,date_trunc('month',b.work_date)::date period_start,sum(b.hours)hours
  from pg_temp._approved_time_basis b where b.profile_kind='historical_payroll'group by 1,2,3
 ), refs as materialized(
  select h.profile_id,h.hours,f.*,
   coalesce(f.original#>>'{_humla_cost_rule,original_fact_id}',f.fact_id)original_fact,
   nullif(replace(replace((regexp_match(coalesce(f.description,f.original->>'Verifikationstext',''),'\[Tot:[[:space:]]*([0-9., ]+)[[:space:]]*tim\]','i'))[1],',','.'),' ',''),'')::numeric reference_hours
  from file_hours h join private.hub_kpi_prepared_facts f on f.tenant_id=p_tenant and f.generation_id=p_generation and f.project=h.project
   and date_trunc('month',f.occurred_on)::date=h.period_start and f.source='NEXT'and f.kind='cost'and f.account='7010'
   and f.original->>'Verifikation nr'like 'ARB.%'and f.fact_id not like 'approved-time:%'
 ), source_hours as(
  select profile_id,project,date_trunc('month',occurred_on)::date period_start,original_fact,max(reference_hours)hours
  from refs where reference_hours>0 group by 1,2,3,4
 ), ratios as(
  select s.profile_id,s.project,s.period_start,least(h.hours/sum(s.hours),1)ratio,sum(s.hours)reference_hours,h.hours file_hours
  from source_hours s join file_hours h using(profile_id,project,period_start)group by s.profile_id,s.project,s.period_start,h.hours
 ), rounded as(
  select r.*,x.ratio,x.reference_hours total_reference_hours,x.file_hours,
   round(r.amount*x.ratio,2)piece,
   row_number()over(partition by r.profile_id,r.project,date_trunc('month',r.occurred_on)order by r.fact_id)seq,
   count(*)over(partition by r.profile_id,r.project,date_trunc('month',r.occurred_on))parts,
   sum(r.amount)over(partition by r.profile_id,r.project,date_trunc('month',r.occurred_on))total_amount
  from refs r join ratios x on x.profile_id=r.profile_id and x.project=r.project and x.period_start=date_trunc('month',r.occurred_on)::date
 )select r.*,-case when seq=parts then round(total_amount*ratio,2)-sum(piece)over(partition by profile_id,project,date_trunc('month',occurred_on))+piece else piece end offset_amount from rounded r;
 if exists(select 1 from pg_temp._approved_time_offsets where abs(offset_amount)>abs(amount)+0.01)then raise exception 'Reference offset exceeds original cost';end if;
 insert into private.hub_kpi_prepared_facts
 select p_generation,p_tenant,extract(year from b.work_date)::int-case when extract(month from b.work_date)<9 then 1 else 0 end,
  'approved-time:'||b.profile_id||':row:'||b.row_id,b.work_date,'cost',b.cost,
  case when b.role='REP'then 'service_repair'else 'personnel'end,b.project,u.registration,u.unit_id,u.unit_name,
  coalesce(bg.name,'Ej klassificerat'),case when b.profile_kind='historical_payroll'then 'NEXT-schablon'else 'Verkstadsschablon'end,
  case when b.role='REP'then 'Preliminär verkstadskostnad från godkänd NEXT-tid'else 'Godkänd historisk personalschablon från NEXT-tid'end,
  null,ib.file_name,b.row_number,e.evidence,b.cost_center,
  coalesce(cc.cost_center_name,case b.cost_center when '30'then 'Transport'when '20'then 'Sortergården'when '40'then 'Verkstad'else 'Ej klassificerat'end),
  jsonb_build_object('source','approved_time_cost_profile','profile_id',b.profile_id,'canonical_person_id',b.person_id,'canonical_project_id',k.object_id),e.evidence
 from pg_temp._approved_time_basis b join private.hub_time_cost_profiles p on p.id=b.profile_id
 join public.kpi_import_batches ib on ib.id=b.batch_id and ib.tenant_id=p_tenant
 left join lateral(select (array_agg(distinct object_id))[1]object_id from public.hub_identity_keys where tenant_id=p_tenant and identity_type='next_project_number'and identity_value=b.project and confidence=1 having count(distinct object_id)=1)k on true
 left join lateral(
  select case when count(distinct o.id)=1 then (array_agg(distinct o.id))[1]end unit_id,
   case when count(distinct o.id)=1 then max(v.period->>'name')end unit_name,
   case when count(distinct o.id)=1 then max(v.period#>>'{main_vehicle,source_reference}')end registration,
   case when count(distinct o.id)=1 then max(v.period->>'business_group_id')end group_id
  from public.hub_objects o cross join lateral jsonb_array_elements(coalesce(o.data->'periods','[]'))v(period)
  where o.tenant_id=p_tenant and o.object_type='EconomicUnit'and coalesce((v.period->>'enabled')::boolean,false)
   and(v.period->>'valid_from')::date<=b.work_date and(nullif(v.period->>'valid_to','')is null or(v.period->>'valid_to')::date>=b.work_date)
   and exists(select 1 from jsonb_array_elements(coalesce(v.period->'members','[]'))m where m->>'kind'='project'and m->>'object_id'=k.object_id::text)
 )u on true
 left join public.kpi_business_groups bg on bg.tenant_id=p_tenant and bg.id::text=u.group_id
 left join lateral(select c.cost_center_name from private.hub_kpi_prepared_kpi_project_classification_periods c where c.tenant_id=p_tenant and c.generation_id=p_generation and c.project_reference=b.project and c.valid_from<=b.work_date and(c.valid_to is null or c.valid_to>=b.work_date)order by c.valid_from desc limit 1)cc on true
 cross join lateral(select jsonb_build_object('actual_payroll',false,'_humla_approved_time',jsonb_build_object('profile_id',b.profile_id,'row_id',b.row_id,'person_id',b.person_id,'hours',b.hours,'covered_transpa_hours',b.covered_hours,'gap_hours',b.gap_hours,'regular_hours',b.regular_hours,'overtime_hours',b.overtime_hours,'monthly_salary',p.monthly_salary,'load_factor',p.load_factor,'weekly_hours',p.weekly_hours,'overtime_multiplier',p.overtime_multiplier,'kind',b.profile_kind,'role',b.role,'approval',p.approval_reference)) evidence)e
 where b.gap_hours>0;
 insert into private.hub_kpi_prepared_facts
 select f.generation_id,f.tenant_id,f.fiscal_year,'approved-time:'||f.profile_id||':offset:'||f.fact_id,f.occurred_on,f.kind,f.offset_amount,f.category,f.project,f.vehicle,f.unit_id,f.unit_name,f.business_group,
  f.source,'Avräkning av motsvarande NEXT-arbetstidskostnad mot godkänd schablon',f.account,f.file_name,f.row_number,
  f.original||jsonb_build_object('_humla_approved_time_offset',e.evidence),f.cost_center,f.cost_center_name,
  f.classification_source||jsonb_build_object('approved_time_offset',e.evidence),f.display_original||jsonb_build_object('_humla_approved_time_offset',e.evidence)
 from pg_temp._approved_time_offsets f cross join lateral(select jsonb_build_object('profile_id',f.profile_id,'source_fact_id',f.fact_id,'source_amount',f.amount,'reference_hours',f.total_reference_hours,'file_hours',f.file_hours,'replacement_ratio',f.ratio,'offset_amount',f.offset_amount,'method','bounded_project_month_proportion') evidence)e
 where f.offset_amount<>0;
 insert into private.hub_kpi_prepared_display_facts
 select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original
 from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id like 'approved-time:%'
 and not exists(select 1 from private.hub_kpi_prepared_display_facts d where d.tenant_id=f.tenant_id and d.generation_id=f.generation_id and d.fact_id=f.fact_id);
 insert into private.hub_time_cost_publications(tenant_id,generation_id,profile_id,summary,created_by)
 select p_tenant,p_generation,p.id,jsonb_build_object('hours',coalesce((select sum(b.hours)from pg_temp._approved_time_basis b where b.profile_id=p.id),0),
  'covered_hours',coalesce((select sum(b.covered_hours)from pg_temp._approved_time_basis b where b.profile_id=p.id),0),
  'gap_hours',coalesce((select sum(b.gap_hours)from pg_temp._approved_time_basis b where b.profile_id=p.id),0),
  'cost',coalesce((select sum(b.cost)from pg_temp._approved_time_basis b where b.profile_id=p.id),0),
  'reference_offset',coalesce((select sum(x.offset_amount)from pg_temp._approved_time_offsets x where x.profile_id=p.id),0)),auth.uid()
 from private.hub_time_cost_profiles p where p.tenant_id=p_tenant and p.enabled and not exists(select 1 from private.hub_time_cost_publications x where x.tenant_id=p_tenant and x.generation_id=p_generation and x.profile_id=p.id);
 get diagnostics n=row_count;
 select jsonb_build_object('published_profiles',n,'positive_cost',(select coalesce(sum(cost),0)from pg_temp._approved_time_basis),'reference_offset',(select coalesce(sum(offset_amount),0)from pg_temp._approved_time_offsets))into answer;
 drop table pg_temp._approved_time_basis;drop table pg_temp._approved_time_offsets;
 return answer;
end $$;
revoke all on function private.hub_publish_approved_time_costs_v1(uuid,uuid)from public,anon,authenticated;
-- Reused for every future generation, before confirmed shared-cost allocation.
do $migration$
declare d text;needle text:='perform private.hub_apply_cost_allocation_v1(job.tenant_id,generation);';
begin
 d:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 if strpos(d,needle)=0 then raise exception 'Unexpected report publication sequence';end if;
 execute replace(d,needle,'perform private.hub_publish_approved_time_costs_v1(job.tenant_id,generation);'||chr(10)||needle);
end $migration$;
