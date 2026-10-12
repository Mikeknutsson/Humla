-- Integration-layer keys for source rows, not a parallel vehicle/project identity.
create or replace function private.hub_workify_import_key_v1(p_date date,p_amount numeric,p_quantity numeric,p_source jsonb,p_content boolean)
returns text language plpgsql immutable set search_path='' as $function$
declare qty numeric; q text; signature jsonb;
begin
 q:=nullif(replace(replace(trim(p_source->>'Kvantitet'),chr(160),''),' ',''),'');
 if q like '%,%' and q like '%.%' then
  if strpos(reverse(q),',')<strpos(reverse(q),'.') then q:=replace(replace(q,'.',''),',','.');else q:=replace(q,',','');end if;
 else q:=replace(q,',','.');end if;
 begin qty:=coalesce(q::numeric,p_quantity); exception when invalid_text_representation or numeric_value_out_of_range then qty:=p_quantity;end;
 signature:=jsonb_build_array(nullif(trim(p_source->>'Ordernummer'),''),nullif(trim(p_source->>'Artikelnummer'),''),p_date,upper(trim(coalesce(p_source->>'RegNr',''))),nullif(trim(p_source->>'Littranummer'),''));
 if p_content then signature:=signature||jsonb_build_array(trim_scale(p_amount),trim_scale(qty),nullif(trim(p_source->>'Enhet'),''),nullif(trim(p_source->>'ArtikelKommentar'),''));end if;
 return encode(extensions.digest(signature::text,'sha256'),'hex');
end $function$;
revoke execute on function private.hub_workify_import_key_v1(date,numeric,numeric,jsonb,boolean) from public,anon;
grant execute on function private.hub_workify_import_key_v1(date,numeric,numeric,jsonb,boolean) to authenticated,service_role;
drop index if exists public.kpi_workify_content_lookup;
drop index if exists public.kpi_workify_base_lookup;
create index if not exists kpi_workify_content_lookup on public.kpi_import_rows(tenant_id,private.hub_workify_import_key_v1(occurred_on,amount,quantity,source_data,true)) where data_kind='revenue';
create index if not exists kpi_workify_base_lookup on public.kpi_import_rows(tenant_id,private.hub_workify_import_key_v1(occurred_on,amount,quantity,source_data,false)) where data_kind='revenue';

create or replace function public.hub_kpi_ingest_workify_file_v1(p_tenant_id uuid,p_batch_id uuid,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='60s' set jit='off' set work_mem='64MB'
as $function$
declare result jsonb; conflicts jsonb; received integer; inserted integer; valid integer; ignored integer; existing_result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>50000 then raise exception 'Ogiltig Workify-leverans';end if;
 perform pg_advisory_xact_lock(hashtextextended('workify-file-import:'||p_tenant_id::text,0));
 select provenance->'workify_import_result' into existing_result from public.kpi_import_batches
 where tenant_id=p_tenant_id and id=p_batch_id and data_kind='revenue' for update;
 if not found then raise exception 'Intäktsimporten saknas';end if;
 if existing_result is not null then return existing_result;end if;
 if exists(select 1 from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows) r
 where (r.vehicle_object_id is not null and not exists(select 1 from public.hub_objects o where o.id=r.vehicle_object_id and o.tenant_id=p_tenant_id))
 or (r.employee_object_id is not null and not exists(select 1 from public.hub_objects o where o.id=r.employee_object_id and o.tenant_id=p_tenant_id)))
 then raise exception 'Objektet tillhör inte arbetsytan' using errcode='42501';end if;
 received:=jsonb_array_length(p_rows);
 select count(*) into ignored from jsonb_array_elements(p_rows) x where (x->>'amount')::numeric=0;
 with incoming as materialized(
  select r.*,private.hub_workify_import_key_v1(r.occurred_on,r.amount,r.quantity,r.source_data,true) fp,
   private.hub_workify_import_key_v1(r.occurred_on,r.amount,r.quantity,r.source_data,false) base
  from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows)r where r.amount is distinct from 0
 ), keys as(select distinct base from incoming), previous as materialized(
  select r.batch_id,private.hub_workify_import_key_v1(r.occurred_on,r.amount,r.quantity,r.source_data,true) fp,
   k.base,count(*) copies
  from keys k join public.kpi_import_rows r on r.tenant_id=p_tenant_id and r.data_kind='revenue'
   and private.hub_workify_import_key_v1(r.occurred_on,r.amount,r.quantity,r.source_data,false)=k.base
  group by r.batch_id,k.base,private.hub_workify_import_key_v1(r.occurred_on,r.amount,r.quantity,r.source_data,true)
 ), known as(select base,fp,max(copies) copies from previous group by base,fp),
 incoming_counts as(select base,fp,count(*) copies from incoming group by base,fp),
 unsafe_bases as(
  select distinct k.base from known k left join incoming_counts i using(base,fp)
  where coalesce(i.copies,0)<k.copies
 ), new_variants as(
  select i.* from incoming i where not exists(select 1 from known k where k.fp=i.fp)
   and exists(select 1 from unsafe_bases b where b.base=i.base)
 )
 select coalesce(jsonb_agg(jsonb_build_object('row',row_number,'order',source_data->>'Ordernummer','date',occurred_on,'amount',amount,'reason','Befintliga källrader har ändrats eller saknas i samma order/artikel/datum. Inget belopp skrivs över automatiskt.')),'[]') into conflicts from new_variants;
 if jsonb_array_length(conflicts)>0 then
  result:=jsonb_build_object('status','blocked_changes','receivedRows',received,'insertedRows',0,'changedRows',jsonb_array_length(conflicts),'changes',conflicts);
  update public.kpi_import_batches set status='needs_review',completed_at=now(),valid_row_count=0,invalid_row_count=received,
   error_summary=conflicts,provenance=provenance||jsonb_build_object('workify_import_result',result)
  where tenant_id=p_tenant_id and id=p_batch_id;
  return result;
 end if;
 with incoming as materialized(
  select r.*,private.hub_workify_import_key_v1(r.occurred_on,r.amount,r.quantity,r.source_data,true) fp
  from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows)r where r.amount is distinct from 0
 ), numbered as materialized(select i.*,row_number()over(partition by fp order by row_number) occurrence from incoming i),
 fingerprints as(select distinct fp from numbered),
 previous as materialized(
  select r.batch_id,f.fp,count(*) copies from fingerprints f join public.kpi_import_rows r
   on r.tenant_id=p_tenant_id and r.data_kind='revenue'
   and private.hub_workify_import_key_v1(r.occurred_on,r.amount,r.quantity,r.source_data,true)=f.fp
  group by r.batch_id,f.fp
 ), known as(select fp,max(copies) copies from previous group by fp),
 accepted as(select n.* from numbered n left join known k using(fp) where n.occurrence>coalesce(k.copies,0)),
 saved as(
  insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,vehicle_object_id,vehicle_registration,employee_object_id,employee_number,project_reference,cost_center,account,description,quantity,amount,currency,available_hours,occupied_hours,paid_hours,billable_hours,is_valid,validation_errors,source_data,allocation,source_system,external_transaction_id,source_fingerprint)
  select p_tenant_id,p_batch_id,row_number,'revenue',occurred_on,vehicle_object_id,vehicle_registration,employee_object_id,employee_number,project_reference,cost_center,account,description,quantity,amount,coalesce(currency,'SEK'),available_hours,occupied_hours,paid_hours,billable_hours,is_valid,coalesce(validation_errors,'[]'),source_data,allocation,'workify_file',
   'workify-file-v1:'||fp||':'||occurrence,'workify-file-v1:'||fp||':'||occurrence from accepted
  on conflict(tenant_id,data_kind,source_fingerprint)where source_fingerprint is not null do nothing returning is_valid
 )
 select count(*),count(*)filter(where is_valid) into inserted,valid from saved;
 result:=jsonb_build_object('status',case when inserted=valid then 'completed' else 'needs_review' end,'receivedRows',received,'insertedRows',inserted,'duplicateRowsSkipped',received-ignored-inserted,'ignoredZeroRows',ignored,'validRows',valid,'invalidRows',inserted-valid,'changedRows',0);
 update public.kpi_import_batches set row_count=inserted,valid_row_count=valid,invalid_row_count=inserted-valid,completed_at=now(),
  status=case when inserted=valid then 'completed' else 'needs_review' end,
  provenance=provenance||jsonb_build_object('workify_import_result',result)
 where tenant_id=p_tenant_id and id=p_batch_id;
 return result;
end $function$;
revoke execute on function public.hub_kpi_ingest_workify_file_v1(uuid,uuid,jsonb) from public,anon;
grant execute on function public.hub_kpi_ingest_workify_file_v1(uuid,uuid,jsonb) to authenticated,service_role;
notify pgrst,'reload schema';
