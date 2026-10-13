-- Bounded administrative steps; the active KPI generation changes only after validation.
create table private.hub_workify_activation_items(
 run_id uuid not null references private.hub_workify_activation_runs(id),
 row_id uuid not null,tenant_id uuid not null,action text not null,canonical_row_id uuid not null,
 before_row jsonb not null,derived_source jsonb not null,applied_at timestamptz,
 primary key(run_id,row_id,action)
);
alter table private.hub_workify_activation_items enable row level security;
revoke all on private.hub_workify_activation_items from public,anon,authenticated;
create index hub_workify_unapplied_items on private.hub_workify_activation_items(run_id,row_id) where applied_at is null;

create or replace function private.hub_workify_apply_approved_review_v1(p_tenant uuid,p_expected jsonb,p_approval_reference text)
returns jsonb language plpgsql set search_path='' set statement_timeout='90s' set jit='off' set work_mem='64MB' as $$
declare controls jsonb; before_hash text; run_id uuid; staged integer;
begin
 if length(trim(coalesce(p_approval_reference,'')))<10 then raise exception 'Approval reference required';end if;
 perform pg_advisory_xact_lock(hashtextextended('workify-file-import:'||p_tenant::text,0));
 -- Compute the expensive historic classification once, then use its frozen result.
 create temporary table hub_workify_approval_work on commit drop as
 select * from private.hub_workify_review_rows_v1(p_tenant);
 analyze hub_workify_approval_work;
 select jsonb_agg(to_jsonb(t)order by currency,review_state) into controls from(
  select currency,review_state,count(*) rows,sum(amount)::text amount
  from pg_temp.hub_workify_approval_work group by 1,2
 )t;
 if controls is distinct from p_expected then raise exception 'Approved source scope changed; activation aborted';end if;
 select md5(string_agg(md5(to_jsonb(r)::text),',' order by r.id)) into before_hash from public.kpi_import_rows r where tenant_id=p_tenant;
 insert into private.hub_workify_activation_runs(tenant_id,approval_reference,expected_controls,original_hash,previous_generation,result)
 select p_tenant,p_approval_reference,controls,before_hash,active_generation,jsonb_build_object('duplicateDecisions',0,'statusDecisions',0,'originalsPreserved',true)
 from private.hub_kpi_report_state where tenant_id=p_tenant returning id into run_id;
 if run_id is null then raise exception 'Prepared KPI state missing';end if;
 with observed as materialized(
  select p.row_id,p.canonical_row_id,p.source_data,r.created_at,
   private.hub_workify_effective_source_v1(r.id,r.source_data) observed_source
  from pg_temp.hub_workify_approval_work p join public.kpi_import_rows r on r.id=p.row_id and r.tenant_id=p_tenant
  where p.review_state in ('candidate_include','candidate_duplicate','excluded_status')
 ), ranked as materialized(
  select o.*,first_value(observed_source)over(partition by canonical_row_id
   order by private.hub_workify_status_rank_v1(observed_source->>'Orderstatus') desc,
   (nullif(observed_source->>'ExterntDokumentnummer','') is not null) desc,created_at desc,row_id) latest
  from observed o
 ), decisions as (
  select * from ranked where row_id<>canonical_row_id
   or latest->>'Orderstatus' is distinct from source_data->>'Orderstatus'
   or latest->>'Fakturerad' is distinct from source_data->>'Fakturerad'
   or latest->>'ExterntDokumentnummer' is distinct from source_data->>'ExterntDokumentnummer'
 )
 insert into private.hub_workify_activation_items(run_id,row_id,tenant_id,action,canonical_row_id,before_row,derived_source)
 select run_id,d.row_id,p_tenant,case when d.row_id<>d.canonical_row_id then 'duplicate' else 'status_update' end,
 d.canonical_row_id,to_jsonb(r),d.latest from decisions d join public.kpi_import_rows r on r.id=d.row_id and r.tenant_id=p_tenant;
 get diagnostics staged=row_count;
 return jsonb_build_object('runId',run_id,'stagedDecisions',staged,'originalsPreserved',true);
end $$;

create or replace function private.hub_workify_apply_activation_chunk_v1(p_run uuid,p_limit integer default 200)
returns jsonb language plpgsql set search_path='' set statement_timeout='30s' as $$
declare run record; changes jsonb; remaining integer;
begin
 if p_limit is null or p_limit<1 or p_limit>500 then raise exception 'Invalid chunk size';end if;
 select * into run from private.hub_workify_activation_runs where id=p_run for update;
 if not found then raise exception 'Activation run missing';end if;
 perform pg_advisory_xact_lock(hashtextextended('workify-file-import:'||run.tenant_id::text,0));
 with selected as materialized(
  select * from private.hub_workify_activation_items where run_id=p_run and applied_at is null order by row_id limit p_limit for update
 ), saved as (
  insert into private.hub_workify_reconciliation_audit(row_id,tenant_id,action,canonical_row_id,before_row,derived_source)
  select row_id,tenant_id,action,canonical_row_id,before_row,derived_source from selected on conflict do nothing returning action
 ), marked as (
  update private.hub_workify_activation_items i set applied_at=clock_timestamp() from selected s
  where i.run_id=s.run_id and i.row_id=s.row_id and i.action=s.action returning i.row_id
 )
 select jsonb_build_object('duplicateDecisions',count(*)filter(where action='duplicate'),'statusDecisions',count(*)filter(where action='status_update')) into changes from saved;
 select count(*) into remaining from private.hub_workify_activation_items where run_id=p_run and applied_at is null;
 update private.hub_workify_activation_runs set result=coalesce(result,'{}')||jsonb_build_object(
  'duplicateDecisions',coalesce((result->>'duplicateDecisions')::int,0)+(changes->>'duplicateDecisions')::int,
  'statusDecisions',coalesce((result->>'statusDecisions')::int,0)+(changes->>'statusDecisions')::int,
  'remainingDecisions',remaining) where id=p_run;
 return changes||jsonb_build_object('remainingDecisions',remaining);
end $$;
revoke all on function private.hub_workify_apply_activation_chunk_v1(uuid,integer) from public,anon,authenticated;
grant execute on function private.hub_workify_apply_activation_chunk_v1(uuid,integer) to service_role;

-- A partially applied run cannot publish a generation.
do $migration$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('private.hub_workify_validate_approved_generation_v1(uuid,uuid)'::regprocedure);
 needle:='if not found then return;end if;';
 if strpos(definition,needle)=0 then raise exception 'Unexpected approved-generation validator';end if;
 definition:=replace(definition,needle,needle||chr(10)||'if exists(select 1 from private.hub_workify_activation_items where run_id=run.id and applied_at is null) then raise exception ''Approval decisions still pending'';end if;');
 execute definition;
end $migration$;
