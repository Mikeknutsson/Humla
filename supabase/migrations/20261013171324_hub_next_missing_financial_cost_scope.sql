-- Financial completeness does not imply a verified vehicle allocation.
create function private.hub_next_completeness_rows_v1(p_tenant uuid)
returns table(row_id uuid,canonical_row_id uuid,review_state text,occurred_on date,project text,
 account text,amount numeric,currency text,batch_id uuid,row_number integer,source_data jsonb)
language sql stable set search_path='' as $$
 with raw as materialized (
 select r.*,b.status batch_status,coalesce(b.provenance,'{}')?'withdrawal' withdrawn,
 exists(select 1 from public.kpi_cost_category_rules c where c.tenant_id=r.tenant_id and c.account=r.account
 and c.valid_from<=r.occurred_on and(c.valid_to is null or c.valid_to>=r.occurred_on)) mapped_account,
 encode(extensions.digest(jsonb_build_array(r.occurred_on,trim_scale(r.amount),trim_scale(r.quantity),
 coalesce(nullif(r.currency,''),'SEK'),r.account,r.project_reference,r.source_data-'Upparb intäkt')::text,'sha256'),'hex') k
 from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 where r.tenant_id=p_tenant and r.data_kind='cost'
 ), numbered as (
 select r.*,row_number()over(partition by k,batch_id order by row_number,id) occ
 from raw r where not withdrawn and batch_status in('completed','needs_review')
 ), ranked as (
 select n.*,first_value(id)over(partition by k,occ order by is_valid desc,created_at,batch_id,row_number,id) canonical from numbered n
 ), states as (
 select r.*,case
 when occurred_on is null or amount is null or amount::text in('NaN','Infinity','-Infinity') then 'invalid_economic'
 when id<>canonical then 'reexport'
 when is_valid then 'current_scope'
 when amount=0 then 'ignored_zero'
 when lower(source_data->>'Inkludera i rapporter') is distinct from 'true' then 'source_policy_review'
 when not mapped_account then 'account_rule_review'
 when jsonb_typeof(coalesce(validation_errors,'[]'))<>'array' then 'validation_review'
 when exists(select 1 from jsonb_array_elements_text(coalesce(validation_errors,'[]'))e
 where e not in('Kostnadsfördelning behöver granskas','Fordonsbeteckning saknar verifierad regnummerkoppling')) then 'validation_review'
 when coalesce(source_data->>'Verifikation nr','') !~ '^[0-9]{2}D[0-9]+$'
 or nullif(trim(source_data->>'Leverantör'),'') is null
 or source_data->>'Leverantör' ~* 'elleholms' or account='4015' then 'source_policy_review'
 else 'candidate_include_unallocated' end state from ranked r
 )
 select id,canonical,state,occurred_on,project_reference,account,amount,coalesce(currency,'SEK'),batch_id,row_number,source_data from states
 union all
 select id,id,case when withdrawn then 'withdrawn' else 'batch_review' end,occurred_on,project_reference,account,amount,
 coalesce(currency,'SEK'),batch_id,row_number,source_data from raw where withdrawn or batch_status not in('completed','needs_review') or batch_status is null;
$$;
revoke all on function private.hub_next_completeness_rows_v1(uuid) from public,anon,authenticated;
grant execute on function private.hub_next_completeness_rows_v1(uuid) to service_role;

create table private.hub_next_completeness_runs (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,previous_generation uuid not null,
 expected_rows bigint not null,expected_amount numeric not null,original_hash text not null,
 approval_reference text not null,status text not null default 'pending',verified_generation uuid,
 verified_at timestamptz,result jsonb
);
create unique index hub_next_one_pending_completion on private.hub_next_completeness_runs(tenant_id) where status='pending';
alter table private.hub_next_completeness_runs enable row level security;
revoke all on private.hub_next_completeness_runs from public,anon,authenticated;
create table private.hub_next_completeness_items (
 row_id uuid primary key references public.kpi_import_rows(id),run_id uuid not null references private.hub_next_completeness_runs(id),
 tenant_id uuid not null,amount numeric not null,occurred_on date not null,account text not null,
 evidence jsonb not null,created_at timestamptz not null default clock_timestamp()
);
alter table private.hub_next_completeness_items enable row level security;
revoke all on private.hub_next_completeness_items from public,anon,authenticated;
grant select on private.hub_next_completeness_items to authenticated;
create policy next_completion_read on private.hub_next_completeness_items for select to authenticated
 using(auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));

create function private.hub_next_completion_source_v1(p_row uuid,p_source jsonb)
returns jsonb language sql stable set search_path='' as $$
 select p_source||case when exists(select 1 from private.hub_next_completeness_items where row_id=p_row)
 then jsonb_build_object('_humla_allocation_review',true,'_humla_next_completion',true,'_humla_next_source_row_id',p_row)
 else '{}'::jsonb end;
$$;
revoke all on function private.hub_next_completion_source_v1(uuid,jsonb) from public,anon;
grant execute on function private.hub_next_completion_source_v1(uuid,jsonb) to authenticated,service_role;

do $migration$
declare definition text;needle text;signature text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_import_row_in_scope_v2(uuid,text,date,numeric,boolean,jsonb,jsonb)'::regprocedure);
 needle:='else coalesce(p_valid,false) and (p_kind<>''revenue'' or p_amount<>0)';
 if strpos(definition,needle)=0 then raise exception 'Unexpected financial predicate';end if;
 execute replace(definition,needle,'else (coalesce(p_valid,false) or (p_kind=''cost'' and exists(select 1 from private.hub_next_completeness_items where row_id=p_row))) and (p_kind<>''revenue'' or p_amount<>0)');
 foreach signature in array array['private.hub_kpi_financial_facts_v1(uuid,date,date)','private.hub_kpi_financial_month_facts_v1(uuid,date,date,integer[])'] loop
 definition:=pg_get_functiondef(signature::regprocedure);
 needle:='x.source_data||jsonb_build_object(''_humla_include_in_vehicle_result'',cr.include_in_vehicle_result)';
 if strpos(definition,needle)=0 then raise exception 'Unexpected NEXT projection: %',signature;end if;
 definition:=replace(definition,needle,'private.hub_next_completion_source_v1(x.id,x.source_data)||jsonb_build_object(''_humla_include_in_vehicle_result'',cr.include_in_vehicle_result)');
 needle:='where f.k=''cost'' and f.src=''NEXT'' and f.raw#>>''{_humla_assignment,shared_cost}'' not in (''none'','''')';
 if strpos(definition,needle)=0 then raise exception 'Unexpected shared-cost scope: %',signature;end if;
 definition:=replace(definition,needle,needle||' and coalesce(f.raw->>''_humla_allocation_review'',''false'')<>''true''');
 execute definition;
 end loop;
end $migration$;

create function private.hub_next_validate_completeness_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql set search_path='' as $$
declare run record;actual_rows bigint;actual_amount numeric;raw_hash text;
begin
 select * into run from private.hub_next_completeness_runs where tenant_id=p_tenant and status='pending' for update;
 if not found then return;end if;
 select count(distinct split_part(f.fact_id,':',1)),sum(f.amount) into actual_rows,actual_amount
 from private.hub_kpi_prepared_facts f join private.hub_next_completeness_items i
 on i.row_id::text=split_part(f.fact_id,':',1) and i.tenant_id=f.tenant_id
 where f.generation_id=p_generation and i.run_id=run.id and f.kind='cost' and f.source='NEXT';
 if actual_rows is distinct from run.expected_rows or actual_amount is distinct from run.expected_amount then raise exception 'NEXT completeness differs from expected scope';end if;
 if exists(select 1 from private.hub_kpi_prepared_facts f join private.hub_next_completeness_items i
 on i.row_id::text=split_part(f.fact_id,':',1) and i.tenant_id=f.tenant_id where f.generation_id=p_generation and i.run_id=run.id
 and (f.vehicle is not null or f.unit_id is not null or f.original->>'_humla_next_completion' is distinct from 'true')) then raise exception 'Uncertain NEXT allocation was assigned';end if;
 if exists(
 with old_facts as(select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=run.previous_generation),
 other_new_facts as(select f.* from private.hub_kpi_prepared_facts f where tenant_id=p_tenant and generation_id=p_generation
 and not exists(select 1 from private.hub_next_completeness_items i where i.run_id=run.id and i.tenant_id=p_tenant and i.row_id::text=split_part(f.fact_id,':',1)))
 select 1 from old_facts o full join other_new_facts n using(fact_id)
 where row(o.occurred_on,o.kind,o.amount,o.category,o.project,o.vehicle,o.unit_id,o.unit_name,o.business_group,o.source,o.cost_center)
 is distinct from row(n.occurred_on,n.kind,n.amount,n.category,n.project,n.vehicle,n.unit_id,n.unit_name,n.business_group,n.source,n.cost_center)
 ) then raise exception 'NEXT completeness changed other financial rows';end if;
 select md5(string_agg(md5(to_jsonb(r)::text),','order by r.id)) into raw_hash from public.kpi_import_rows r where tenant_id=p_tenant;
 if raw_hash is distinct from run.original_hash then raise exception 'Original imports changed';end if;
 update private.hub_next_completeness_runs set status='verified',verified_generation=p_generation,verified_at=clock_timestamp(),
 result=jsonb_build_object('addedRows',actual_rows,'addedAmount',actual_amount,'difference',actual_amount-run.expected_amount,
 'originalsPreserved',true,'otherFactsPreserved',true,'allocationReview',true) where id=run.id;
end $$;
revoke all on function private.hub_next_validate_completeness_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function private.hub_next_validate_completeness_v1(uuid,uuid) to service_role;
do $migration$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 needle:='perform private.hub_next_validate_reexport_generation_v1(job.tenant_id,generation);';
 if strpos(definition,needle)=0 then raise exception 'Unexpected report validation';end if;
 execute replace(definition,needle,'perform private.hub_next_validate_completeness_v1(job.tenant_id,generation);'||chr(10)||needle);
end $migration$;
