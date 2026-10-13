-- Read-only proposal. No original rows, prepared facts or active generation are changed.
create or replace function private.hub_workify_financially_eligible_v1(p_valid boolean,p_errors jsonb)
returns boolean language sql immutable set search_path='' as $$
 select not(coalesce(p_errors,'[]') ?| array[
  'Importen återtagen eller ersatt; ingår inte i beräkningar',
  'Fakturan finns i NeXT intäktsbokföring; fakturaunderlag räknas inte som ytterligare intäkt'])
 and (coalesce(p_valid,false) or (coalesce(p_errors,'[]')<>'[]'::jsonb and not exists(
  select 1 from jsonb_array_elements_text(coalesce(p_errors,'[]')) e
  where e not in ('Kostnadsfördelning behöver granskas','Fordonsbeteckning saknar verifierad regnummerkoppling','Workify-artikeln ska till fordon: registreringsnummer behöver mappas')
   and e not like 'Ej mappad Workify-artikel:%')));
$$;
revoke all on function private.hub_workify_financially_eligible_v1(boolean,jsonb) from public,anon,authenticated;
grant execute on function private.hub_workify_financially_eligible_v1(boolean,jsonb) to service_role;

create or replace function private.hub_workify_review_rows_v1(p_tenant uuid)
returns table(row_id uuid,batch_id uuid,row_number integer,occurred_on date,amount numeric,currency text,
 order_number text,original_status text,effective_status text,review_state text,reason text,
 canonical_row_id uuid,allocation_review boolean,source_data jsonb,validation_errors jsonb)
language sql stable set search_path='' as $$
 with source as materialized (
  select r.id,r.batch_id,r.row_number,r.occurred_on,r.amount,r.quantity,coalesce(nullif(r.currency,''),'SEK') currency,
   r.source_data,r.validation_errors,r.is_valid,r.created_at,r.source_fingerprint,
   private.hub_workify_effective_source_v1(r.id,r.source_data) observed,
   private.hub_workify_financially_eligible_v1(r.is_valid,r.validation_errors) financially_eligible
  from public.kpi_import_rows r where r.tenant_id=p_tenant and r.data_kind='revenue' and r.source_data ? 'Ordernummer'
 ), signatures as materialized (
  select s.*,private.hub_workify_content_key_v2(occurred_on,amount,quantity,observed-'ExterntDokumentnummer')||':'||currency||':'||financially_eligible::text sig
  from source s
 ), refs as (
  select sig,max(nullif(observed->>'ExterntDokumentnummer','')) doc,
   max(private.hub_workify_status_rank_v1(observed->>'Orderstatus'))filter(where nullif(observed->>'ExterntDokumentnummer','') is not null) status_rank
  from signatures group by sig having count(distinct nullif(observed->>'ExterntDokumentnummer',''))=1
 ), completed as materialized (
  select s.*,case when nullif(observed->>'ExterntDokumentnummer','') is null
    and private.hub_workify_status_rank_v1(observed->>'Orderstatus')<r.status_rank
    then observed||jsonb_build_object('ExterntDokumentnummer',r.doc) else observed end projected
  from signatures s left join refs r using(sig)
 ), keyed as (
  select c.*,private.hub_workify_content_key_v2(occurred_on,amount,quantity,projected)||':'||currency||':'||financially_eligible::text fp
  from completed c
 ), numbered as (
  select k.*,case when source_fingerprint ~ '^workify-file-v[12]:[a-f0-9]+:[0-9]+$'
   then split_part(source_fingerprint,':',3)::bigint
   else row_number()over(partition by fp,batch_id order by row_number,id) end occurrence
  from keyed k
 ), ranked as materialized (
  select n.*,first_value(id)over(partition by fp,occurrence order by is_valid desc,created_at,row_number,id) canonical_id,
   first_value(projected->>'Orderstatus')over(partition by fp,occurrence
    order by private.hub_workify_status_rank_v1(projected->>'Orderstatus') desc,created_at desc,id) latest_status
  from numbered n
 ), classified as (
  select r.*,case
   when amount is null or amount::text in ('NaN','Infinity','-Infinity') or occurred_on is null then 'invalid'
   when amount=0 then 'ignored_zero'
   when nullif(trim(source_data->>'Ordernummer'),'') is null then 'review_required'
   when coalesce(validation_errors,'[]') ? 'Importen återtagen eller ersatt; ingår inte i beräkningar' then 'excluded_withdrawn'
   when coalesce(validation_errors,'[]') ? 'Fakturan finns i NeXT intäktsbokföring; fakturaunderlag räknas inte som ytterligare intäkt' then 'excluded_accounted_elsewhere'
   when not financially_eligible then 'review_required'
   when id<>canonical_id then 'candidate_duplicate'
   when coalesce(latest_status,'') not in ('Reported','ReadyForInvoicing','Invoiced') then 'excluded_status'
   else 'candidate_include' end state
  from ranked r
 )
 select id,batch_id,row_number,occurred_on,amount,currency,source_data->>'Ordernummer',source_data->>'Orderstatus',latest_status,state,
  case state when 'candidate_include' then 'content_occurrence_requires_approval'
   when 'candidate_duplicate' then 'same_content_occurrence_across_imports'
   when 'excluded_status' then 'outside_three_eligible_statuses'
   when 'review_required' then 'identity_or_financial_validation_unresolved'
   else state end,
  canonical_id,not coalesce(is_valid,false),source_data,validation_errors from classified;
$$;
revoke all on function private.hub_workify_review_rows_v1(uuid) from public,anon,authenticated;
grant execute on function private.hub_workify_review_rows_v1(uuid) to service_role;

create or replace function public.hub_workify_review_v1(p_tenant_id uuid,p_page integer default 0,p_state text default 'all')
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='60s' set jit='off' set work_mem='64MB' as $$
declare result jsonb;
begin
 if auth.uid() is null or public.hub_has_permission(p_tenant_id,'kpi.read') is distinct from true then
  raise exception 'KPI access required' using errcode='42501';end if;
 if p_page is null or p_page<0 or p_page>100000 then raise exception 'Invalid page';end if;
 if p_state is null or p_state not in ('all','candidate_include','candidate_duplicate','excluded_status','ignored_zero','invalid','review_required','excluded_withdrawn','excluded_accounted_elsewhere') then raise exception 'Invalid state';end if;
 with rows as materialized(select * from private.hub_workify_review_rows_v1(p_tenant_id)),
 prepared as materialized (
  -- Material split facts retain the original UUID before ':material'. Sum all components once.
  select split_part(f.fact_id,':',1) source_row_id,count(*) fact_count,sum(f.amount) amount
  from private.hub_kpi_prepared_facts f join private.hub_kpi_report_state s
   on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
  where f.tenant_id=p_tenant_id and f.kind='revenue' group by 1
 ), compared as materialized (
  select r.*,coalesce(p.fact_count,0) prepared_facts,coalesce(p.amount,0) prepared_amount
  from rows r left join prepared p on p.source_row_id=r.row_id::text
 ), totals as (
  select currency,review_state,count(*) rows,
   coalesce(sum(amount)filter(where amount::text not in ('NaN','Infinity','-Infinity')),0)::text source_amount,
   coalesce(sum(prepared_amount),0)::text current_prepared_amount,
   count(*)filter(where prepared_facts=0) missing_from_prepared_rows,
   count(*)filter(where allocation_review) allocation_review_rows
  from compared group by 1,2
 ), months as (
  select date_trunc('month',occurred_on)::date as month,currency,
   sum(prepared_amount)::text current_amount,
   coalesce(sum(prepared_amount)filter(where review_state='candidate_include'),0)::text retained_current_amount,
   coalesce(sum(prepared_amount)filter(where review_state='candidate_duplicate'),0)::text duplicate_candidate_amount,
   coalesce(sum(prepared_amount)filter(where review_state='excluded_status'),0)::text status_excluded_amount,
   coalesce(sum(prepared_amount)filter(where review_state not in ('candidate_include','candidate_duplicate','excluded_status')),0)::text other_held_amount,
   count(*)filter(where review_state='candidate_include' and prepared_facts=0) missing_candidate_rows
  from compared group by 1,2
 ), controls as (
  select currency,count(*) rows,
   coalesce(sum(amount)filter(where amount::text not in ('NaN','Infinity','-Infinity')),0)::text raw_amount,
   sum(prepared_amount)::text current_prepared_amount,
   (sum(prepared_amount)-coalesce(sum(prepared_amount)filter(where review_state='candidate_include'),0)
    -coalesce(sum(prepared_amount)filter(where review_state<>'candidate_include'),0))::text partition_difference
  from compared group by currency
 ), items as (
  select c.*,b.file_name from compared c join public.kpi_import_batches b on b.id=c.batch_id and b.tenant_id=p_tenant_id
  where p_state='all' or c.review_state=p_state
  order by c.occurred_on nulls first,c.order_number,c.row_id limit 100 offset p_page*100
 )
 select jsonb_build_object('mode','comparison_only','approved',false,'totalRows',(select count(*)from rows),
  'selectedRows',(select count(*)from rows where p_state='all' or review_state=p_state),
  'selectedState',p_state,'page',p_page,'pageSize',100,
  'activeGeneration',(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant_id),
  'totals',coalesce((select jsonb_agg(to_jsonb(t)order by currency,review_state)from totals t),'[]'),
  'months',coalesce((select jsonb_agg(to_jsonb(m)order by month,currency)from months m),'[]'),
  'controls',coalesce((select jsonb_agg(to_jsonb(c))from controls c),'[]'),
  'items',coalesce((select jsonb_agg((to_jsonb(i)-'amount'-'prepared_amount')||jsonb_build_object('amount',i.amount::text,'prepared_amount',i.prepared_amount::text))from items i),'[]')) into result;
 return result;
end $$;
revoke all on function public.hub_workify_review_v1(uuid,integer,text) from public,anon;
grant execute on function public.hub_workify_review_v1(uuid,integer,text) to authenticated,service_role;
notify pgrst,'reload schema';
