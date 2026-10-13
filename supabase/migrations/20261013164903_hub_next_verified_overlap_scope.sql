-- Re-export decisions are separate from immutable source imports.
create table private.hub_next_reexport_audit (
 row_id uuid primary key references public.kpi_import_rows(id),
 tenant_id uuid not null, canonical_row_id uuid not null references public.kpi_import_rows(id),
 content_key text not null, occurrence bigint not null, evidence jsonb not null,
 created_at timestamptz not null default clock_timestamp(), check(row_id<>canonical_row_id)
);
alter table private.hub_next_reexport_audit enable row level security;
revoke all on private.hub_next_reexport_audit from public,anon,authenticated;
grant select on private.hub_next_reexport_audit to authenticated;
create policy next_reexport_read on private.hub_next_reexport_audit for select to authenticated
 using(auth.uid() is not null and public.hub_has_permission(tenant_id,'kpi.read'));

create function private.hub_next_reexport_candidates_v1(p_tenant uuid)
returns table(row_id uuid,canonical_row_id uuid,content_key text,occurrence bigint)
language sql stable set search_path='' as $$
 with base as materialized (
 select r.id,r.batch_id,r.row_number,r.created_at,
 encode(extensions.digest(jsonb_build_array(r.occurred_on,trim_scale(r.amount),trim_scale(r.quantity),
 coalesce(nullif(r.currency,''),'SEK'),r.account,r.project_reference,r.source_data-'Upparb intäkt')::text,'sha256'),'hex') k
 from public.kpi_import_rows r join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 where r.tenant_id=p_tenant and r.data_kind='cost' and r.is_valid and r.occurred_on is not null
 and r.amount is not null and r.amount::text not in('NaN','Infinity','-Infinity')
 and r.source_data ?& array['Konto','Projektnr','Verifikation nr']
 and nullif(trim(r.source_data->>'Verifikation nr'),'') is not null
 and b.status in('completed','needs_review') and not(coalesce(b.provenance,'{}')?'withdrawal')
 ), numbered as(select b.*,row_number()over(partition by k,batch_id order by row_number,id) occ from base b),
 ranked as(select n.*,first_value(id)over(partition by k,occ order by created_at,batch_id,row_number,id) canonical from numbered n)
 select id,canonical,k,occ from ranked where id<>canonical;
$$;
revoke all on function private.hub_next_reexport_candidates_v1(uuid) from public,anon,authenticated;
grant execute on function private.hub_next_reexport_candidates_v1(uuid) to service_role;

create function private.hub_next_record_reexports_v1(p_tenant uuid,p_reference text)
returns bigint language plpgsql set search_path='' as $$
declare n bigint;
begin
 perform pg_advisory_xact_lock(hashtextextended('next-reexport:'||p_tenant::text,0));
 insert into private.hub_next_reexport_audit(row_id,tenant_id,canonical_row_id,content_key,occurrence,evidence)
 select row_id,p_tenant,canonical_row_id,content_key,occurrence,
 jsonb_build_object('method','identical_export_row_with_preserved_batch_multiplicity','ignored_column','Upparb intäkt','reference',p_reference)
 from private.hub_next_reexport_candidates_v1(p_tenant) on conflict(row_id) do nothing;
 get diagnostics n=row_count;return n;
end $$;
revoke all on function private.hub_next_record_reexports_v1(uuid,text) from public,anon,authenticated;
grant execute on function private.hub_next_record_reexports_v1(uuid,text) to service_role;

-- Every existing financial producer already consumes this shared Hub predicate.
do $migration$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_import_row_in_scope_v2(uuid,text,date,numeric,boolean,jsonb,jsonb)'::regprocedure);
 needle:='else coalesce(p_valid,false) and (p_kind<>''revenue'' or p_amount<>0) end;';
 if strpos(definition,needle)=0 then raise exception 'Unexpected financial scope';end if;
 execute replace(definition,needle,'else coalesce(p_valid,false) and (p_kind<>''revenue'' or p_amount<>0)
 and (p_kind<>''cost'' or not exists(select 1 from private.hub_next_reexport_audit where row_id=p_row)) end;');
end $migration$;

-- Run once after a future file has finished, never between its upload chunks.
create function private.hub_next_finished_import_v1() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.data_kind='cost' and new.status in('completed','needs_review') and old.status is distinct from new.status then
  if auth.uid() is null or not public.hub_has_permission(new.tenant_id,'kpi.manage') then raise exception 'KPI management required';end if;
  perform private.hub_next_record_reexports_v1(new.tenant_id,'Completed NEXT export overlap check');
 end if;return new;
end $$;
revoke all on function private.hub_next_finished_import_v1() from public,anon,authenticated;
create trigger hub_next_finished_import after update of status on public.kpi_import_batches
 for each row execute function private.hub_next_finished_import_v1();

create table private.hub_next_reexport_activation (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,
 previous_generation uuid not null,original_hash text not null,expected_rows bigint not null,
 expected_removed numeric not null,approval_reference text not null,status text not null default 'pending',
 verified_generation uuid,verified_at timestamptz,result jsonb
);
alter table private.hub_next_reexport_activation enable row level security;
revoke all on private.hub_next_reexport_activation from public,anon,authenticated;

create function private.hub_next_validate_reexport_generation_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql set search_path='' as $$
declare run record;actual_rows bigint;actual_removed numeric;raw_hash text;
begin
 select * into run from private.hub_next_reexport_activation where tenant_id=p_tenant and status='pending' for update;
 if not found then return;end if;
 select count(distinct a.row_id),sum(f.amount) into actual_rows,actual_removed
 from private.hub_next_reexport_audit a join private.hub_kpi_prepared_facts f
 on f.tenant_id=a.tenant_id and split_part(f.fact_id,':',1)=a.row_id::text
 where a.tenant_id=p_tenant and f.generation_id=run.previous_generation and f.kind='cost';
 if actual_rows is distinct from run.expected_rows or actual_removed is distinct from run.expected_removed then raise exception 'NEXT approved overlap scope changed';end if;
 if exists(
 with expected as(select f.* from private.hub_kpi_prepared_facts f where tenant_id=p_tenant and generation_id=run.previous_generation
 and not exists(select 1 from private.hub_next_reexport_audit a where a.tenant_id=p_tenant and a.row_id::text=split_part(f.fact_id,':',1) and f.kind='cost')),
 actual as(select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation)
 select 1 from expected o full join actual n using(fact_id)
 where row(o.occurred_on,o.kind,o.amount,o.category,o.project,o.vehicle,o.unit_id,o.unit_name,o.business_group,o.source,o.cost_center)
 is distinct from row(n.occurred_on,n.kind,n.amount,n.category,n.project,n.vehicle,n.unit_id,n.unit_name,n.business_group,n.source,n.cost_center)
 ) then raise exception 'NEXT generation changed other financial rows';end if;
 select md5(string_agg(md5(to_jsonb(r)::text),',' order by r.id)) into raw_hash from public.kpi_import_rows r where tenant_id=p_tenant;
 if raw_hash is distinct from run.original_hash then raise exception 'Original imports changed';end if;
 update private.hub_next_reexport_activation set status='verified',verified_generation=p_generation,verified_at=clock_timestamp(),
 result=jsonb_build_object('removedRows',actual_rows,'removedAmount',actual_removed,'difference',0,'originalsPreserved',true,'otherFactsPreserved',true) where id=run.id;
end $$;
revoke all on function private.hub_next_validate_reexport_generation_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function private.hub_next_validate_reexport_generation_v1(uuid,uuid) to service_role;
do $migration$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 needle:='perform private.hub_workify_validate_approved_generation_v1(job.tenant_id,generation);';
 if strpos(definition,needle)=0 then raise exception 'Unexpected report validator';end if;
 execute replace(definition,needle,'perform private.hub_next_validate_reexport_generation_v1(job.tenant_id,generation);'||chr(10)||needle);
end $migration$;
