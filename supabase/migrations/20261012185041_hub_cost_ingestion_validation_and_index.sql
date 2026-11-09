create or replace function public.hub_kpi_ingest_cost_file_v1(p_tenant_id uuid,p_batch_id uuid,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='60s' set jit='off' set work_mem='64MB' as $$
declare received int; inserted_count int; valid_count int; result jsonb; existing_result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>50000 then raise exception 'Ogiltig kostnadsleverans';end if;
 perform pg_advisory_xact_lock(hashtextextended('cost-file-import:'||p_tenant_id::text,0));
 select provenance->'hub_cost_ingest_result' into existing_result from public.kpi_import_batches where id=p_batch_id and tenant_id=p_tenant_id and data_kind='cost' for update;
 if not found then raise exception 'Kostnadsimporten saknas';end if;
 if existing_result is not null then return existing_result;end if;
 received:=jsonb_array_length(p_rows);
 if exists(select 1 from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows) r where r.data_kind is distinct from 'cost') then raise exception 'Endast kostnadsrader tillåts';end if;
 if exists(select 1 from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows) r where (r.vehicle_object_id is not null and not exists(select 1 from public.hub_objects o where o.id=r.vehicle_object_id and o.tenant_id=p_tenant_id))
 or (r.employee_object_id is not null and not exists(select 1 from public.hub_objects o where o.id=r.employee_object_id and o.tenant_id=p_tenant_id))) then raise exception 'Fordon tillhör inte arbetsytan' using errcode='42501';end if;
 with parsed as materialized(
 select r.*,
 coalesce((select jsonb_agg(e) from jsonb_array_elements_text(coalesce(r.validation_errors,'[]')) e
 where e not in ('Kostnadsfördelning behöver granskas','Fordonsbeteckning saknar verifierad regnummerkoppling')),'[]') financial_errors
 from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows) r
 ), normalized as materialized(
 select (jsonb_populate_record(null::public.kpi_import_rows,to_jsonb(r)||jsonb_build_object(
 'is_valid',r.financial_errors='[]'::jsonb and r.amount is not null and r.amount::text not in ('NaN','Infinity','-Infinity') and r.occurred_on is not null,
 'validation_errors',r.financial_errors,
 'vehicle_registration',case when r.vehicle_registration ~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then r.vehicle_registration end,
 'allocation',coalesce(r.allocation,'{}')||jsonb_build_object('allocation_status',case when r.vehicle_object_id is not null then 'verified' else 'unallocated' end)
 ))).* from parsed r
 ), incoming as materialized (
 select r.*,private.hub_economic_key_v2('cost',r.occurred_on,r.amount,r.quantity,r.currency,r.source_data,md5(r.source_data::text)) fp
 from normalized r
 ), numbered as materialized (
 select i.*,row_number() over(partition by fp order by row_number) as occurrence from incoming i
 ), fingerprints as (select distinct fp from numbered),
 previous as materialized (
 select private.hub_economic_key_v2('cost',r.occurred_on,r.amount,r.quantity,r.currency,r.source_data,md5(r.source_data::text)) fp,r.batch_id,count(*) copies
 from public.kpi_import_rows r where r.tenant_id=p_tenant_id and r.data_kind='cost'
 and not(coalesce(r.validation_errors,'[]') ? 'Importen återtagen eller ersatt; ingår inte i beräkningar')
 and exists(select 1 from fingerprints f where f.fp=private.hub_economic_key_v2('cost',r.occurred_on,r.amount,r.quantity,r.currency,r.source_data,md5(r.source_data::text)))
 group by 1,2
 ), known as (select fp,max(copies) copies from previous group by fp),
 accepted as (select n.* from numbered n left join known k using(fp) where n.occurrence>coalesce(k.copies,0)),
 saved as (
 insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,vehicle_object_id,vehicle_registration,employee_object_id,employee_number,project_reference,cost_center,account,description,quantity,amount,currency,available_hours,occupied_hours,paid_hours,billable_hours,is_valid,validation_errors,source_data,allocation,source_system,external_transaction_id,source_fingerprint)
 select p_tenant_id,p_batch_id,row_number,'cost',occurred_on,vehicle_object_id,vehicle_registration,employee_object_id,employee_number,project_reference,cost_center,account,description,quantity,amount,coalesce(currency,'SEK'),available_hours,occupied_hours,paid_hours,billable_hours,is_valid,coalesce(validation_errors,'[]'::jsonb),source_data,allocation,'next_file','next-file-v1:'||fp||':'||occurrence,'next-file-v1:'||fp||':'||occurrence from accepted
 on conflict(tenant_id,data_kind,source_fingerprint) where source_fingerprint is not null do nothing returning is_valid
 )
 select count(*),count(*) filter(where is_valid) into inserted_count,valid_count from saved;
 result:=jsonb_build_object('status',case when inserted_count=valid_count then 'completed' else 'needs_review' end,'receivedRows',received,'insertedRows',inserted_count,'duplicateRowsSkipped',received-inserted_count,'validRows',valid_count,'invalidRows',inserted_count-valid_count);
 update public.kpi_import_batches set row_count=inserted_count,valid_row_count=valid_count,invalid_row_count=inserted_count-valid_count,completed_at=now(),status=case when inserted_count=valid_count then 'completed' else 'needs_review' end,provenance=provenance||jsonb_build_object('hub_cost_ingest_result',result) where id=p_batch_id and tenant_id=p_tenant_id;
 return result;
end $$;
revoke all on function public.hub_kpi_ingest_cost_file_v1(uuid,uuid,jsonb) from public,anon;
grant execute on function public.hub_kpi_ingest_cost_file_v1(uuid,uuid,jsonb) to authenticated;
create index if not exists kpi_next_economic_content_lookup on public.kpi_import_rows(
 tenant_id,private.hub_economic_key_v2('cost',occurred_on,amount,quantity,currency,source_data,md5(source_data::text))
) where data_kind='cost';

