-- Read-only classification proposal. Set humla.review_tenant to the authorized tenant before running.
-- Content/occurrence matching is evidence, not a source-issued row ID.
 with source as materialized(select r.*,private.hub_workify_content_key_v2(occurred_on,amount,quantity,source_data-'ExterntDokumentnummer') sig
  from public.kpi_import_rows r where tenant_id=current_setting('humla.review_tenant')::uuid and data_kind='revenue' and is_valid and amount<>0 and nullif(source_data->>'Ordernummer','') is not null),
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
  from numbered n)
 select count(*) raw_rows,sum(amount)::text raw_amount,
 count(*)filter(where id=canonical_id) candidate_unique_rows,
 sum(amount)filter(where id=canonical_id)::text candidate_unique_amount,
 count(*)filter(where id<>canonical_id) duplicate_candidate_rows,
 sum(amount)filter(where id<>canonical_id)::text duplicate_candidate_amount,
 count(*)filter(where latest->>'Orderstatus' in ('Reported','ReadyForInvoicing','Invoiced') and id=canonical_id) eligible_candidate_rows,
 sum(amount)filter(where latest->>'Orderstatus' in ('Reported','ReadyForInvoicing','Invoiced') and id=canonical_id)::text eligible_candidate_amount,
 (sum(amount)-coalesce(sum(amount)filter(where id=canonical_id),0)-coalesce(sum(amount)filter(where id<>canonical_id),0))::text partition_difference
 from ranked;
