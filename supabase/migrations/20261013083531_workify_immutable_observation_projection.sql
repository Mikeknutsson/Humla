-- Preserve the existing original-row audit trigger. Derived state is separate.
create or replace function public.hub_kpi_ingest_workify_file_v1(p_tenant_id uuid,p_batch_id uuid,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='60s' set jit='off' set work_mem='64MB'
as $function$
declare result jsonb; known jsonb; plan jsonb; conflicts jsonb; received integer; inserted integer; valid integer; ignored integer; updated integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>50000 then raise exception 'Ogiltig Workify-leverans';end if;
 perform pg_advisory_xact_lock(hashtextextended('workify-file-import:'||p_tenant_id::text,0));
 select provenance->'workify_import_result' into result from public.kpi_import_batches
 where tenant_id=p_tenant_id and id=p_batch_id and data_kind='revenue' for update;
 if not found then raise exception 'Intäktsimporten saknas';end if;
 if result is not null then return result;end if;
 if exists(select 1 from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows) r
 where (r.vehicle_object_id is not null and not exists(select 1 from public.hub_objects o where o.id=r.vehicle_object_id and o.tenant_id=p_tenant_id))
 or (r.employee_object_id is not null and not exists(select 1 from public.hub_objects o where o.id=r.employee_object_id and o.tenant_id=p_tenant_id)))
 then raise exception 'Objektet tillhör inte arbetsytan' using errcode='42501';end if;
 if exists(select 1 from jsonb_array_elements(p_rows) r where (r->>'row_number')::int is null)
 or (select count(*) from jsonb_array_elements(p_rows))<>(select count(distinct r->>'row_number') from jsonb_array_elements(p_rows)r)
 then raise exception 'Varje källrad måste ha ett unikt radnummer inom filen';end if;
 received:=jsonb_array_length(p_rows);
 select count(*) into ignored from jsonb_array_elements(p_rows)r where (r->>'amount')::numeric=0;
 -- Include all older observations when deriving occurrence capacity, including
 -- retained duplicate originals. Incremental v2 inserts carry explicit ordinals.
 with orders as(select distinct r#>>'{source_data,Ordernummer}' number from jsonb_array_elements(p_rows)r),
 previous as materialized(select r.*,private.hub_workify_content_key_v2(r.occurred_on,r.amount,r.quantity,r.source_data) fp
  from public.kpi_import_rows r join orders o on o.number=r.source_data->>'Ordernummer'
  where r.tenant_id=p_tenant_id and r.data_kind='revenue'),
 batches as(select fp,source_data->>'Ordernummer' order_number,batch_id,count(*) copies,
  max(case when source_fingerprint ~ '^workify-file-v[12]:[a-f0-9]+:[0-9]+$' then split_part(source_fingerprint,':',3)::bigint else 0 end) ordinal
  from previous group by 1,2,3),
 capacity as(select fp,order_number,greatest(max(copies),max(ordinal)) copies from batches group by 1,2)
 select coalesce(jsonb_agg(to_jsonb(c)),'[]') into known from capacity c;
 select coalesce(jsonb_agg(to_jsonb(p)),'[]') into plan from private.hub_workify_import_plan_v2(p_rows,known)p;
 select coalesce(jsonb_agg(jsonb_build_object('row',p.row_number,'order',p.order_number,'amount',r->'amount',
  'reason','Radidentiteten är osäker: tidigare innehåll saknas samtidigt som nytt innehåll tillkommer. Hela leveransen väntar på granskning.')),'[]') into conflicts
 from jsonb_to_recordset(plan) as p(row_number int,order_number text,decision text)
 join jsonb_array_elements(p_rows) r on (r->>'row_number')::int=p.row_number where p.decision='blocked';
 if jsonb_array_length(conflicts)>0 then
  insert into private.hub_workify_row_observations(tenant_id,batch_id,row_number,content_key,occurrence,decision,source_data,amount)
  select p_tenant_id,p_batch_id,p.row_number,p.fp,p.occurrence,'blocked',coalesce(r->'source_data','{}'),(r->>'amount')::numeric
  from jsonb_to_recordset(plan) as p(row_number int,fp text,occurrence bigint)
  join jsonb_array_elements(p_rows)r on (r->>'row_number')::int=p.row_number;
  result:=jsonb_build_object('status','blocked_changes','receivedRows',received,'insertedRows',0,'changedRows',jsonb_array_length(conflicts),'changes',conflicts);
  update public.kpi_import_batches set status='needs_review',completed_at=now(),valid_row_count=0,invalid_row_count=received,
   error_summary=conflicts,provenance=coalesce(provenance,'{}')||jsonb_build_object('workify_import_result',result)
  where tenant_id=p_tenant_id and id=p_batch_id;
  return result;
 end if;
 with accepted as(select r.*,p.fp,p.occurrence from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows)r
  join jsonb_to_recordset(plan)as p(row_number int,fp text,occurrence bigint,decision text)using(row_number) where p.decision='insert'),
 saved as(insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,vehicle_object_id,vehicle_registration,employee_object_id,employee_number,project_reference,cost_center,account,description,quantity,amount,currency,available_hours,occupied_hours,paid_hours,billable_hours,is_valid,validation_errors,source_data,allocation,source_system,external_transaction_id,source_fingerprint)
  select p_tenant_id,p_batch_id,row_number,'revenue',occurred_on,vehicle_object_id,vehicle_registration,employee_object_id,employee_number,project_reference,cost_center,account,description,quantity,amount,coalesce(currency,'SEK'),available_hours,occupied_hours,paid_hours,billable_hours,is_valid,coalesce(validation_errors,'[]'),source_data,allocation,'workify_file',
   'workify-file-v2:'||fp||':'||occurrence,'workify-file-v2:'||fp||':'||occurrence from accepted returning is_valid)
 select count(*),count(*)filter(where is_valid) into inserted,valid from saved;
 -- Original rows are immutable. Status advances are observations below.
 updated:=0;
 insert into private.hub_workify_row_observations(tenant_id,batch_id,row_number,content_key,occurrence,decision,source_data,amount)
 select p_tenant_id,p_batch_id,p.row_number,p.fp,p.occurrence,p.decision,coalesce(r->'source_data','{}'),(r->>'amount')::numeric
 from jsonb_to_recordset(plan)as p(row_number int,fp text,occurrence bigint,decision text)
 join jsonb_array_elements(p_rows)r on (r->>'row_number')::int=p.row_number;
 with mapped as(
  select coalesce(a.canonical_row_id,x.id) id,
   private.hub_workify_content_key_v2(x.occurred_on,x.amount,x.quantity,x.source_data) fp,
   coalesce(k.created_at,x.created_at) created_at,coalesce(k.row_number,x.row_number) row_number,
   coalesce(k.is_valid,x.is_valid) is_valid
  from public.kpi_import_rows x
  left join private.hub_workify_reconciliation_audit a on a.row_id=x.id and a.action='duplicate'
  left join public.kpi_import_rows k on k.id=a.canonical_row_id
  where x.tenant_id=p_tenant_id and x.data_kind='revenue'
   and private.hub_workify_content_key_v2(x.occurred_on,x.amount,x.quantity,x.source_data) in(select p.fp from jsonb_to_recordset(plan)as p(fp text))
 ), canonical as(select distinct on(fp,id) * from mapped order by fp,id,is_valid desc,created_at,row_number),
 candidates as(select c.*,row_number()over(partition by fp order by is_valid desc,created_at,row_number,id) occurrence from canonical c)
 update private.hub_workify_row_observations o set canonical_row_id=c.id from candidates c
 where o.batch_id=p_batch_id and o.tenant_id=p_tenant_id and o.content_key=c.fp and o.occurrence=c.occurrence;
 select count(*) into updated from private.hub_workify_row_observations o join public.kpi_import_rows x on x.id=o.canonical_row_id
 where o.batch_id=p_batch_id and private.hub_workify_status_rank_v1(o.source_data->>'Orderstatus')>private.hub_workify_status_rank_v1(x.source_data->>'Orderstatus');
 result:=jsonb_build_object('status',case when inserted=valid then 'completed' else 'needs_review' end,'receivedRows',received,'insertedRows',inserted,'duplicateRowsSkipped',received-ignored-inserted,'ignoredZeroRows',ignored,'validRows',valid,'invalidRows',inserted-valid,'changedRows',0,'statusObservations',updated);
 update public.kpi_import_batches set row_count=inserted,valid_row_count=valid,invalid_row_count=inserted-valid,completed_at=now(),
  status=case when inserted=valid then 'completed' else 'needs_review' end,
  provenance=coalesce(provenance,'{}')||jsonb_build_object('workify_import_result',result)
 where tenant_id=p_tenant_id and id=p_batch_id;
 return result;
end $function$;
revoke execute on function public.hub_kpi_ingest_workify_file_v1(uuid,uuid,jsonb) from public,anon;
grant execute on function public.hub_kpi_ingest_workify_file_v1(uuid,uuid,jsonb) to authenticated,service_role;
notify pgrst,'reload schema';

alter table private.hub_workify_reconciliation_audit add column if not exists derived_source jsonb;
create index if not exists hub_workify_observation_row_lookup on private.hub_workify_row_observations(canonical_row_id,observed_at);

create or replace function private.hub_workify_effective_source_v1(p_row uuid,p_original jsonb)
returns jsonb language sql stable set search_path='' as $$
 with evidence as(
  select p_original data,0 priority, '-infinity'::timestamptz observed_at
  union all select derived_source,1,recorded_at from private.hub_workify_reconciliation_audit where row_id=p_row and action='status_update' and derived_source is not null
  union all select source_data,2,observed_at from private.hub_workify_row_observations where canonical_row_id=p_row and decision<>'blocked'
 ), best as(select data from evidence order by private.hub_workify_status_rank_v1(data->>'Orderstatus') desc,
  (nullif(data->>'ExterntDokumentnummer','') is not null) desc,observed_at desc,priority desc limit 1)
 select coalesce(p_original,'{}')||jsonb_build_object('Orderstatus',data->'Orderstatus',
  'Fakturerad',coalesce(nullif(data->>'Fakturerad',''),p_original->>'Fakturerad'),
  'ExterntDokumentnummer',coalesce(nullif(data->>'ExterntDokumentnummer',''),p_original->>'ExterntDokumentnummer')) from best;
$$;
revoke all on function private.hub_workify_effective_source_v1(uuid,jsonb) from public,anon;
grant execute on function private.hub_workify_effective_source_v1(uuid,jsonb) to authenticated,service_role;

create or replace function private.hub_workify_reconcile_history_v2(p_tenant uuid)
returns jsonb language plpgsql set search_path='' set statement_timeout='120s' as $fn$
declare duplicates integer; duplicate_amount numeric;
begin
 perform pg_advisory_xact_lock(hashtextextended('workify-file-import:'||p_tenant::text,0));
 with source as materialized(select r.*,private.hub_workify_content_key_v2(occurred_on,amount,quantity,source_data-'ExterntDokumentnummer') sig
  from public.kpi_import_rows r where tenant_id=p_tenant and data_kind='revenue' and is_valid and amount<>0 and nullif(source_data->>'Ordernummer','') is not null),
 document_refs as(select sig,max(nullif(source_data->>'ExterntDokumentnummer','')) doc,
  max(private.hub_workify_status_rank_v1(source_data->>'Orderstatus'))filter(where nullif(source_data->>'ExterntDokumentnummer','') is not null) status_rank
  from source group by sig having count(distinct nullif(source_data->>'ExterntDokumentnummer',''))=1),
 completed as materialized(select s.*,case when nullif(s.source_data->>'ExterntDokumentnummer','') is null
   and private.hub_workify_status_rank_v1(s.source_data->>'Orderstatus')<c.status_rank
   then s.source_data||jsonb_build_object('ExterntDokumentnummer',c.doc) else s.source_data end observed_source
  from source s left join document_refs c using(sig)),
 keyed as(select c.*,private.hub_workify_content_key_v2(occurred_on,amount,quantity,observed_source) fp from completed c),
 numbered as(select b.*,case when source_fingerprint ~ '^workify-file-v[12]:[a-f0-9]+:[0-9]+$'
  then split_part(source_fingerprint,':',3)::bigint else row_number()over(partition by fp,batch_id order by row_number,id) end occurrence from keyed b),
 ranked as materialized(select n.*,first_value(id)over(partition by fp,occurrence order by created_at,row_number,id) canonical_id,
  first_value(observed_source)over(partition by fp,occurrence order by private.hub_workify_status_rank_v1(observed_source->>'Orderstatus') desc,created_at desc,id) latest
  from numbered n),
 saved as(insert into private.hub_workify_reconciliation_audit(row_id,tenant_id,action,canonical_row_id,before_row,derived_source)
  select r.id,p_tenant,case when r.id<>r.canonical_id then 'duplicate' else 'status_update' end,r.canonical_id,to_jsonb(b),r.latest
  from ranked r join public.kpi_import_rows b on b.id=r.id
  where r.id<>r.canonical_id or r.latest is distinct from r.source_data
  on conflict do nothing returning action,before_row)
 select count(*)filter(where action='duplicate'),coalesce(sum((before_row->>'amount')::numeric)filter(where action='duplicate'),0)
 into duplicates,duplicate_amount from saved;
 return jsonb_build_object('duplicate_rows',duplicates,'duplicate_amount',duplicate_amount,'originals_preserved',true);
end $fn$;
revoke all on function private.hub_workify_reconcile_history_v2(uuid) from public,anon,authenticated;
grant execute on function private.hub_workify_reconcile_history_v2(uuid) to service_role;
