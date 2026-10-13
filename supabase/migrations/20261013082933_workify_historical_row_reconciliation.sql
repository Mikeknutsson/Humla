-- Reversible evidence preservation: original rows are retained, never deleted.
create table if not exists private.hub_workify_reconciliation_audit (
 row_id uuid not null references public.kpi_import_rows(id),
 tenant_id uuid not null references public.hub_tenants(id),
 action text not null,
 canonical_row_id uuid,
 before_row jsonb not null,
 recorded_at timestamptz not null default now(),
 primary key(row_id,action)
);
alter table private.hub_workify_reconciliation_audit enable row level security;
revoke all on private.hub_workify_reconciliation_audit from public,anon,authenticated;

create or replace function private.hub_workify_reconcile_history_v2(p_tenant uuid)
returns jsonb language plpgsql set search_path='' set statement_timeout='120s' as $fn$
declare enriched integer; duplicates integer; duplicate_amount numeric;
begin
 perform pg_advisory_xact_lock(hashtextextended('workify-file-import:'||p_tenant::text,0));
 -- A missing external document reference may be filled only when all other
 -- source content matches, there is one reference and the observed status advanced.
 with source as materialized(select r.*,private.hub_workify_content_key_v2(occurred_on,amount,quantity,source_data-'ExterntDokumentnummer') sig
  from public.kpi_import_rows r where tenant_id=p_tenant and data_kind='revenue' and is_valid and amount<>0 and nullif(source_data->>'Ordernummer','') is not null),
 candidates as(select sig,max(nullif(source_data->>'ExterntDokumentnummer','')) doc,
  max(private.hub_workify_status_rank_v1(source_data->>'Orderstatus'))filter(where nullif(source_data->>'ExterntDokumentnummer','') is not null) status_rank
  from source group by sig having count(distinct nullif(source_data->>'ExterntDokumentnummer',''))=1),
 targets as materialized(select s.id,c.doc from source s join candidates c using(sig)
  where nullif(s.source_data->>'ExterntDokumentnummer','') is null
   and private.hub_workify_status_rank_v1(s.source_data->>'Orderstatus')<c.status_rank),
 audit as(insert into private.hub_workify_reconciliation_audit(row_id,tenant_id,action,before_row)
  select r.id,p_tenant,'document_enrichment',to_jsonb(r) from public.kpi_import_rows r join targets t on t.id=r.id
  on conflict do nothing returning row_id)
 update public.kpi_import_rows r set source_data=r.source_data||jsonb_build_object('ExterntDokumentnummer',t.doc)
 from targets t where r.id=t.id;
 get diagnostics enriched=row_count;

 -- Occurrence is scoped to the content within EACH source file, so two real
 -- identical lines in one file remain two canonical transactions.
 with base as materialized(select r.*,private.hub_workify_content_key_v2(occurred_on,amount,quantity,source_data) fp
  from public.kpi_import_rows r where tenant_id=p_tenant and data_kind='revenue' and is_valid and amount<>0 and nullif(source_data->>'Ordernummer','') is not null),
 numbered as(select b.*,case when source_fingerprint ~ '^workify-file-v[12]:[a-f0-9]+:[0-9]+$' then split_part(source_fingerprint,':',3)::bigint else row_number()over(partition by fp,batch_id order by row_number,id) end occurrence from base b),
 ranked as materialized(select n.*,first_value(id)over(partition by fp,occurrence order by created_at,row_number,id) canonical_id,
  first_value(source_data)over(partition by fp,occurrence order by private.hub_workify_status_rank_v1(source_data->>'Orderstatus') desc,created_at desc,id) latest
  from numbered n),
 evidence as(insert into private.hub_workify_reconciliation_audit(row_id,tenant_id,action,canonical_row_id,before_row)
  select r.id,p_tenant,case when r.id<>r.canonical_id then 'duplicate' else 'status_update' end,r.canonical_id,to_jsonb(b)
  from ranked r join public.kpi_import_rows b on b.id=r.id
  where r.id<>r.canonical_id or private.hub_workify_status_rank_v1(r.latest->>'Orderstatus')>private.hub_workify_status_rank_v1(r.source_data->>'Orderstatus')
  on conflict do nothing returning row_id),
 changed as(update public.kpi_import_rows x set
  is_valid=case when r.id<>r.canonical_id then false else x.is_valid end,
  validation_errors=case when r.id<>r.canonical_id then coalesce(x.validation_errors,'[]')||jsonb_build_array('Workify-dubblett: ekonomin räknas på rad '||r.canonical_id::text) else x.validation_errors end,
  source_data=case when r.id<>r.canonical_id then x.source_data||jsonb_build_object('_humla_workify_duplicate_of',r.canonical_id)
   else x.source_data||jsonb_build_object('Orderstatus',r.latest->>'Orderstatus','Fakturerad',coalesce(nullif(r.latest->>'Fakturerad',''),x.source_data->>'Fakturerad'),
   '_humla_status_history',coalesce(x.source_data->'_humla_status_history','[]')||jsonb_build_array(jsonb_build_object('from',x.source_data->>'Orderstatus','to',r.latest->>'Orderstatus','reason','historical_reconciliation','observed_at',now()))) end
  from ranked r where x.id=r.id and (r.id<>r.canonical_id or private.hub_workify_status_rank_v1(r.latest->>'Orderstatus')>private.hub_workify_status_rank_v1(x.source_data->>'Orderstatus'))
  returning x.amount,r.id<>r.canonical_id duplicate)
 select count(*)filter(where duplicate),coalesce(sum(amount)filter(where duplicate),0) into duplicates,duplicate_amount from changed;
 return jsonb_build_object('duplicate_rows',duplicates,'duplicate_amount',duplicate_amount,'document_references_completed',enriched,'originals_preserved',true);
end $fn$;
revoke all on function private.hub_workify_reconcile_history_v2(uuid) from public,anon,authenticated;
grant execute on function private.hub_workify_reconcile_history_v2(uuid) to service_role;
alter table public.kpi_import_rows add constraint kpi_workify_duplicate_not_active
 check (is_valid is not true or not (coalesce(source_data,'{}') ? '_humla_workify_duplicate_of'));

-- Existing v1 incremental rows also carry occurrence numbers. Do not forget
-- those ordinals when importing again after the v2 rollout.
do $upgrade$
declare definition text;
begin
 definition:=pg_get_functiondef('public.hub_kpi_ingest_workify_file_v1(uuid,uuid,jsonb)'::regprocedure);
 if strpos(definition,$old$source_fingerprint like 'workify-file-v2:%'$old$)=0 then raise exception 'Unexpected Workify intake definition';end if;
 execute replace(definition,$old$source_fingerprint like 'workify-file-v2:%'$old$,$new$source_fingerprint ~ '^workify-file-v[12]:[a-f0-9]+:[0-9]+$'$new$);
end $upgrade$;
