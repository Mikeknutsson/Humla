create table private.hub_workify_activation_runs(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.hub_tenants(id),
 approved_at timestamptz not null default now(),approval_reference text not null,
 expected_controls jsonb not null,original_hash text not null,previous_generation uuid,
 status text not null default 'pending' check(status in ('pending','verified')),
 verified_generation uuid,verified_at timestamptz,result jsonb
);
alter table private.hub_workify_activation_runs enable row level security;
revoke all on private.hub_workify_activation_runs from public,anon,authenticated;
create index hub_workify_pending_activation on private.hub_workify_activation_runs(tenant_id,approved_at) where status='pending';

-- Called by the authorized administrative activation workflow, not a public API.
create or replace function private.hub_workify_apply_approved_review_v1(p_tenant uuid,p_expected jsonb,p_approval_reference text)
returns jsonb language plpgsql set search_path='' set statement_timeout='120s' set jit='off' set work_mem='64MB' as $$
declare controls jsonb; before_hash text; after_hash text; run_id uuid; changes jsonb;
begin
 if length(trim(coalesce(p_approval_reference,'')))<10 then raise exception 'Approval reference required';end if;
 perform pg_advisory_xact_lock(hashtextextended('workify-file-import:'||p_tenant::text,0));
 select jsonb_agg(to_jsonb(t)order by currency,review_state) into controls from(
  select currency,review_state,count(*) rows,sum(amount)::text amount
  from private.hub_workify_review_rows_v1(p_tenant) group by 1,2
 )t;
 if controls is distinct from p_expected then raise exception 'Approved source scope changed; activation aborted';end if;
 select md5(string_agg(md5(to_jsonb(r)::text),',' order by r.id)) into before_hash from public.kpi_import_rows r where tenant_id=p_tenant;
 insert into private.hub_workify_activation_runs(tenant_id,approval_reference,expected_controls,original_hash,previous_generation)
 select p_tenant,p_approval_reference,controls,before_hash,active_generation from private.hub_kpi_report_state where tenant_id=p_tenant
 returning id into run_id;
 if run_id is null then raise exception 'Prepared KPI state missing';end if;
 with reviewed as materialized(select * from private.hub_workify_review_rows_v1(p_tenant)),
 observed as materialized(
  select p.*,r.created_at,to_jsonb(r) before_row,private.hub_workify_effective_source_v1(r.id,r.source_data) observed_source
  from reviewed p join public.kpi_import_rows r on r.id=p.row_id and r.tenant_id=p_tenant
  where p.review_state in ('candidate_include','candidate_duplicate','excluded_status')
 ), ranked as (
  select o.*,first_value(observed_source)over(partition by canonical_row_id
   order by private.hub_workify_status_rank_v1(observed_source->>'Orderstatus') desc,
   (nullif(observed_source->>'ExterntDokumentnummer','') is not null) desc,created_at desc,row_id) latest
  from observed o
 ), saved as (
  insert into private.hub_workify_reconciliation_audit(row_id,tenant_id,action,canonical_row_id,before_row,derived_source)
  select row_id,p_tenant,case when row_id<>canonical_row_id then 'duplicate' else 'status_update' end,canonical_row_id,before_row,latest
  from ranked where row_id<>canonical_row_id
   or latest->>'Orderstatus' is distinct from source_data->>'Orderstatus'
   or latest->>'Fakturerad' is distinct from source_data->>'Fakturerad'
   or latest->>'ExterntDokumentnummer' is distinct from source_data->>'ExterntDokumentnummer'
  on conflict do nothing returning action
 )
 select jsonb_build_object('duplicateDecisions',count(*)filter(where action='duplicate'),'statusDecisions',count(*)filter(where action='status_update')) into changes from saved;
 select md5(string_agg(md5(to_jsonb(r)::text),',' order by r.id)) into after_hash from public.kpi_import_rows r where tenant_id=p_tenant;
 if before_hash is distinct from after_hash then raise exception 'Original imports changed during approval';end if;
 update private.hub_workify_activation_runs set result=changes||jsonb_build_object('originalsPreserved',true) where id=run_id;
 return changes||jsonb_build_object('runId',run_id,'originalsPreserved',true);
end $$;
revoke all on function private.hub_workify_apply_approved_review_v1(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function private.hub_workify_apply_approved_review_v1(uuid,jsonb,text) to service_role;

-- The normal report worker validates the approved rows before publishing a new generation.
create or replace function private.hub_workify_validate_approved_generation_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql set search_path='' as $$
declare run record; expected_rows bigint; expected_amount numeric; actual_rows bigint; actual_amount numeric; originals_hash text; old_cost_hash text; new_cost_hash text;
begin
 select * into run from private.hub_workify_activation_runs where tenant_id=p_tenant and status='pending' order by approved_at desc limit 1 for update;
 if not found then return;end if;
 if (select count(distinct c->>'currency')from jsonb_array_elements(run.expected_controls)c)>1 then raise exception 'Multi-currency activation needs separate reconciliation';end if;
 select (c->>'rows')::bigint,(c->>'amount')::numeric into expected_rows,expected_amount
 from jsonb_array_elements(run.expected_controls)c where c->>'review_state'='candidate_include';
 select count(distinct split_part(f.fact_id,':',1)),coalesce(sum(f.amount),0) into actual_rows,actual_amount
 from private.hub_kpi_prepared_facts f where tenant_id=p_tenant and generation_id=p_generation and kind='revenue' and original ? 'Ordernummer';
 if actual_rows is distinct from expected_rows or actual_amount is distinct from expected_amount then
  raise exception 'Workify generation differs from approved scope: rows %/% amount %/%',actual_rows,expected_rows,actual_amount,expected_amount;end if;
 if exists(select 1 from private.hub_kpi_prepared_facts f join private.hub_workify_reconciliation_audit a
  on a.row_id::text=split_part(f.fact_id,':',1) and a.action='duplicate'
  where f.tenant_id=p_tenant and f.generation_id=p_generation and f.kind='revenue') then raise exception 'Duplicate present in prepared generation';end if;
 if exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation
  and original->>'_humla_allocation_review'='true' and (vehicle is not null or unit_id is not null)) then raise exception 'Uncertain Workify row was allocated';end if;
 -- Check the entire previous cost split, including targets, categories and amounts.
 select md5(string_agg(md5(jsonb_build_array(fact_id,occurred_on,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center)::text),',' order by fact_id))
 into old_cost_hash from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=run.previous_generation and kind='cost';
 select md5(string_agg(md5(jsonb_build_array(fact_id,occurred_on,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center)::text),',' order by fact_id))
 into new_cost_hash from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and kind='cost';
 if old_cost_hash is distinct from new_cost_hash then raise exception 'Existing cost split changed during Workify activation';end if;
 select md5(string_agg(md5(to_jsonb(r)::text),',' order by r.id)) into originals_hash from public.kpi_import_rows r where tenant_id=p_tenant;
 if originals_hash is distinct from run.original_hash then raise exception 'Source imports changed before approved generation completed';end if;
 update private.hub_workify_activation_runs set status='verified',verified_generation=p_generation,verified_at=clock_timestamp(),
 result=result||jsonb_build_object('preparedRows',actual_rows,'preparedAmount',actual_amount,'difference',actual_amount-expected_amount,'costSplitPreserved',true)
 where id=run.id;
end $$;
revoke all on function private.hub_workify_validate_approved_generation_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function private.hub_workify_validate_approved_generation_v1(uuid,uuid) to service_role;

do $migration$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 needle:='phase:=''snapshot''; phase_started:=clock_timestamp();';
 if strpos(definition,needle)=0 then raise exception 'Unexpected report worker snapshot phase';end if;
 definition:=replace(definition,needle,'perform pg_advisory_xact_lock(hashtextextended(''workify-file-import:''||job.tenant_id::text,0));'||chr(10)||needle);
 needle:='update private.hub_kpi_report_generations set completed_at=clock_timestamp() where id=generation;';
 if strpos(definition,needle)=0 then raise exception 'Unexpected report generation activation';end if;
 definition:=replace(definition,needle,'perform private.hub_workify_validate_approved_generation_v1(job.tenant_id,generation);'||chr(10)||needle);
 execute definition;
 definition:=pg_get_functiondef('public.hub_workify_review_v1(uuid,integer,text)'::regprocedure);
 needle:='''mode'',''comparison_only'',''approved'',false';
 if strpos(definition,needle)=0 then raise exception 'Unexpected Workify review metadata';end if;
 definition:=replace(definition,needle,'''mode'',case when exists(select 1 from private.hub_workify_activation_runs where tenant_id=p_tenant_id and status=''verified'') then ''active'' else ''comparison_only'' end,''approved'',exists(select 1 from private.hub_workify_activation_runs where tenant_id=p_tenant_id)');
 execute definition;
end $migration$;
notify pgrst,'reload schema';
