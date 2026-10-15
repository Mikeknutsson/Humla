create or replace function private.hub_approved_time_cost_basis_v1(p_tenant uuid,p_generation uuid)
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
 ), actual_debits as materialized(
 select distinct f.project,f.cost_center,date_trunc('month',f.occurred_on)::date period_start
 from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation
 and f.source='NEXT'and f.kind='cost'and f.account='4630'and f.amount<>0
 and(concat_ws(' ',f.description,f.original->>'Verifikationstext')ilike '%verkstad%'or f.original->>'Verifikation nr'~'^AO[.][0-9]{4}-[0-9]{2}$')
 ), scoped as materialized(
 select s.* from deduped s join private.hub_time_cost_profiles p on p.id=s.profile_id
 left join actual_debits d on d.project=s.project and d.cost_center=s.cost_center and d.period_start=date_trunc('month',s.work_date)::date
 where copy_rank=1 and s.cost_center=any(p.cost_centers)and(s.kind='historical_payroll'or(s.role='REP'and d.project is null))
 ), days as materialized(
  select s.profile_id,s.person_id,s.work_date,sum(s.hours)hours from scoped s group by 1,2,3
 ), gaps as materialized(
  select s.*,case when s.kind='historical_payroll'then least(coalesce(n.hours,0),d.hours)*s.hours/d.hours else 0 end covered,
   case when s.kind='historical_payroll'then greatest(d.hours-coalesce(n.hours,0),0)*s.hours/d.hours else s.hours end gap,
   date_trunc('week',s.work_date)::date week_start,s.code~'^(ÖT|ÖK)'explicit_ot
  from scoped s join days d on d.profile_id=s.profile_id and d.person_id is not distinct from s.person_id and d.work_date=s.work_date
  left join native n on n.person_id=s.person_id and n.work_date=s.work_date
 ), weeks as materialized(
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
