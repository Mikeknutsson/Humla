-- Inspection only: no UPDATE, no ledger refresh, no activation of allocation rules.
-- Content fingerprints identify review candidates; they are not source line IDs.
create or replace function private.hub_cost_review_rows_v1(p_tenant uuid)
returns table(row_id uuid,batch_id uuid,row_number integer,occurred_on date,project text,
 amount numeric,currency text,batch_status text,import_valid boolean,review_state text,
 reason text,candidate_row_id uuid,source_data jsonb,validation_errors jsonb)
language sql stable set search_path='' as $$
 with raw as materialized (
  select r.*,b.status batch_status,
   private.hub_economic_key_v2('cost',r.occurred_on,r.amount,r.quantity,r.currency,r.source_data,r.id::text) candidate_key
  from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
  where r.tenant_id=p_tenant and r.data_kind='cost'
 ), numbered as (
  select r.*,row_number() over(partition by candidate_key,batch_id order by row_number,id) occurrence from raw r
 ), ranked as (
  select n.*,first_value(id) over(partition by candidate_key,occurrence order by created_at,batch_id,row_number,id) candidate
  from numbered n
 )
 select id,batch_id,row_number,occurred_on,project_reference,amount,coalesce(currency,'SEK'),batch_status,is_valid,
  case when amount is null or amount::text in ('NaN','Infinity','-Infinity') or occurred_on is null then 'invalid'
   else 'review_required' end,
  case when amount is null or amount::text in ('NaN','Infinity','-Infinity') or occurred_on is null then 'invalid_economic_data'
   when candidate<>id then 'possible_duplicate_without_source_line_id'
   when batch_status<>'completed' then 'batch_and_source_identity_need_review'
   else 'missing_verified_source_line_id' end,
  case when candidate<>id then candidate end,source_data,validation_errors
 from ranked;
$$;
revoke all on function private.hub_cost_review_rows_v1(uuid) from public,anon,authenticated;
grant execute on function private.hub_cost_review_rows_v1(uuid) to service_role;

create or replace function public.hub_cost_review_v1(p_tenant_id uuid,p_page integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='30s' set jit='off' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then
  raise exception 'KPI access required' using errcode='42501'; end if;
 if p_page is null or p_page<0 or p_page>100000 then raise exception 'Invalid page'; end if;
 with facts as materialized(select * from private.hub_cost_review_rows_v1(p_tenant_id)),
 totals as(select currency,review_state,count(*) rows,
  coalesce(sum(amount)filter(where amount::text not in ('NaN','Infinity','-Infinity')),0)::text amount
  from facts group by 1,2),
 batches as(select currency,batch_status,count(*) rows,sum(amount)::text amount from facts group by 1,2),
 items as(select f.*,b.file_name from facts f join public.kpi_import_batches b on b.id=f.batch_id
  order by f.occurred_on nulls first,f.batch_id,f.row_number,f.row_id limit 100 offset p_page*100)
 select jsonb_build_object('mode','review_only','scope','all_import_history','totalRows',(select count(*)from facts),
  'verifiedUniqueRows',0,'verifiedDuplicateRows',0,
  'possibleDuplicateRows',(select count(*)from facts where candidate_row_id is not null and review_state<>'invalid'),
  'reviewRows',(select count(*)from facts where review_state='review_required'),
  'invalidRows',(select count(*)from facts where review_state='invalid'),
  'totals',coalesce((select jsonb_agg(to_jsonb(t))from totals t),'[]'),
  'batchTotals',coalesce((select jsonb_agg(to_jsonb(b))from batches b),'[]'),
  'activeRules',(select count(*)from public.hub_cost_allocation_rules where tenant_id=p_tenant_id and enabled),
  'inactiveRules',(select count(*)from public.hub_cost_allocation_rules where tenant_id=p_tenant_id and not enabled),
  'financialReconciliationApproved',false,'financialReconciliationDifference',null,
  'partitionDifferenceRows',(select count(*)-count(*)filter(where review_state in ('invalid','review_required'))from facts),
  'page',p_page,'pageSize',100,
  'items',coalesce((select jsonb_agg((to_jsonb(i)-'amount')||jsonb_build_object('amount',i.amount::text))from items i),'[]')) into result;
 return result;
end $$;
revoke all on function public.hub_cost_review_v1(uuid,integer) from public,anon;
grant execute on function public.hub_cost_review_v1(uuid,integer) to authenticated,service_role;

-- Daily evidence is resolved through canonical Hub objects, never by employee number across systems.
create or replace function private.hub_transpa_day_review_rows_v1(p_tenant uuid)
returns table(employee_id text,person_object_id uuid,work_date date,vehicle_object_id uuid,
 review_state text,reason text,report_count bigint,source_report_ids jsonb)
language sql stable set search_path='' as $$
 with keys as materialized (
  select identity_type,identity_value,(array_agg(distinct object_id))[1] object_id
  from public.hub_identity_keys where tenant_id=p_tenant and confidence=1
   and identity_type in ('transpa_employee_id','transpa_vehicle_id')
  group by 1,2 having count(distinct object_id)=1
 ), reports as materialized (
  select t.*,p.object_id canonical_person from public.kpi_transpa_time_facts t
  left join keys p on p.identity_type='transpa_employee_id' and p.identity_value=t.employee_id
  where t.tenant_id=p_tenant and t.work_date>='2025-09-01'
 ), expanded as (
  select r.*,v.object_id canonical_vehicle from reports r
  left join lateral jsonb_array_elements_text(coalesce(r.transpa_vehicle_ids,'[]')) x on true
  left join keys v on v.identity_type='transpa_vehicle_id' and v.identity_value=x.value
 ), days as (
  select employee_id,canonical_person,work_date,count(distinct time_report_id) report_count,
   count(distinct canonical_vehicle) vehicle_count,bool_or(canonical_vehicle is null) missing_vehicle,
   (array_agg(distinct canonical_vehicle)filter(where canonical_vehicle is not null))[1] vehicle,
   jsonb_agg(distinct time_report_id) report_ids
  from expanded group by 1,2,3
 )
 select employee_id,canonical_person,work_date,
  case when vehicle_count=1 and not missing_vehicle and canonical_person is not null then vehicle end,
  case when vehicle_count=1 and not missing_vehicle and canonical_person is not null then 'dated_evidence' else 'review' end,
  case when canonical_person is null then 'missing_canonical_person'
   when missing_vehicle then 'missing_canonical_vehicle'
   when vehicle_count>1 then 'multiple_vehicles_same_day' else 'dated_time_report_evidence' end,
  report_count,report_ids from days;
$$;
revoke all on function private.hub_transpa_day_review_rows_v1(uuid) from public,anon,authenticated;
grant execute on function private.hub_transpa_day_review_rows_v1(uuid) to service_role;

create or replace function public.hub_transpa_day_review_v1(p_tenant_id uuid,p_page integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='30s' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then
  raise exception 'KPI access required' using errcode='42501'; end if;
 if p_page is null or p_page<0 or p_page>100000 then raise exception 'Invalid page'; end if;
 with days as materialized(select * from private.hub_transpa_day_review_rows_v1(p_tenant_id)),
 items as(select d.*,coalesce(p.data->>'display_name',p.data->>'name') person_name,coalesce(v.data->>'display_name',v.data->>'registration') vehicle_name from days d
  left join public.hub_objects p on p.id=d.person_object_id and p.tenant_id=p_tenant_id
  left join public.hub_objects v on v.id=d.vehicle_object_id and v.tenant_id=p_tenant_id
  order by d.work_date desc,d.employee_id limit 100 offset p_page*100)
 select jsonb_build_object('mode','review_only','evidenceType','dated_time_reports','requestedFrom','2025-09-01',
  'firstDate',(select min(work_date)from days),'lastDate',(select max(work_date)from days),
  'totalRows',(select count(*)from days),'evidenceRows',(select count(*)from days where review_state='dated_evidence'),
  'reviewRows',(select count(*)from days where review_state='review'),
  'sourceReports',(select coalesce(sum(report_count),0)from days),'page',p_page,'pageSize',100,
  'items',coalesce((select jsonb_agg(to_jsonb(i))from items i),'[]')) into result;
 return result;
end $$;
revoke all on function public.hub_transpa_day_review_v1(uuid,integer) from public,anon;
grant execute on function public.hub_transpa_day_review_v1(uuid,integer) to authenticated,service_role;
notify pgrst,'reload schema';
