-- Explicit row-level decisions for reexports enriched with a document prefix.
-- Equal amounts alone never establish a duplicate; original rows stay intact.
create function private.hub_workify_comment_enrichment_equal_v1(p_old jsonb,p_new jsonb)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(p_old?'Ordernummer' and p_new?'Ordernummer'
 and (p_old-'ArtikelKommentar')=(p_new-'ArtikelKommentar')
 and p_old->>'ArtikelKommentar'~'(^|[^0-9])[0-9]{8}([^0-9]|$)'
 and p_new->>'ArtikelKommentar'~'^[0-9]{8}[[:space:]]+'
 and regexp_replace(p_new->>'ArtikelKommentar','^[0-9]{8}[[:space:]]+','')=p_old->>'ArtikelKommentar',false)
$$;
revoke all on function private.hub_workify_comment_enrichment_equal_v1(jsonb,jsonb) from public,anon,authenticated;

alter table private.hub_workify_reconciliation_audit add column review_evidence jsonb;
create function private.hub_workify_record_comment_duplicates_v1(p_tenant uuid,p_pairs jsonb,p_reference text)
returns jsonb language plpgsql set search_path='' as $$
declare pair record;original_row public.kpi_import_rows;new_row public.kpi_import_rows;generation uuid;amount_removed numeric:=0;decisions integer:=0;
begin
 if p_pairs is null or jsonb_typeof(p_pairs)<>'array' or jsonb_array_length(p_pairs)not between 1 and 100 or length(trim(coalesce(p_reference,'')))<10 then raise exception 'Explicit duplicate review required';end if;
 perform pg_advisory_xact_lock(hashtextextended('workify-file-import:'||p_tenant::text,0));
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant and status='ready' for update;
 if not found then raise exception 'Published generation required';end if;
 for pair in select * from jsonb_to_recordset(p_pairs)as p(canonical_id uuid,duplicate_id uuid) loop
  select * into strict original_row from public.kpi_import_rows where tenant_id=p_tenant and id=pair.canonical_id and data_kind='revenue';
  select * into strict new_row from public.kpi_import_rows where tenant_id=p_tenant and id=pair.duplicate_id and data_kind='revenue';
  if original_row.id=new_row.id or original_row.batch_id=new_row.batch_id
   or row(original_row.occurred_on,original_row.amount,original_row.currency)is distinct from row(new_row.occurred_on,new_row.amount,new_row.currency)
   or not private.hub_workify_comment_enrichment_equal_v1(original_row.source_data,new_row.source_data)
   or not exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=generation and fact_id=original_row.id::text)
   or not exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=generation and fact_id=new_row.id::text)
   or exists(select 1 from private.hub_workify_reconciliation_audit where row_id=original_row.id and action='duplicate')
   or exists(select 1 from private.hub_workify_reconciliation_audit where row_id=new_row.id and action='duplicate')
  then raise exception 'Duplicate evidence does not match published originals';end if;
  -- Same content repeated within one export may be distinct genuine trips.
  if (select count(*)from public.kpi_import_rows r where r.tenant_id=p_tenant and r.batch_id=original_row.batch_id and r.source_data=original_row.source_data)<>1
   or(select count(*)from public.kpi_import_rows r where r.tenant_id=p_tenant and r.batch_id=new_row.batch_id and r.source_data=new_row.source_data)<>1
  then raise exception 'Ambiguous occurrence multiplicity';end if;
  insert into private.hub_workify_reconciliation_audit(row_id,tenant_id,action,canonical_row_id,before_row,derived_source,review_evidence)
  values(new_row.id,p_tenant,'duplicate',original_row.id,to_jsonb(new_row),new_row.source_data,
   jsonb_build_object('reason','verified_document_prefix_enrichment','reference',p_reference,'previous_generation',generation,'canonical_source',original_row.source_data));
  amount_removed:=amount_removed+new_row.amount;decisions:=decisions+1;
 end loop;
 return jsonb_build_object('rows',decisions,'expectedRevenueRemoved',amount_removed,'originalsPreserved',true,'previousGeneration',generation);
end $$;
revoke all on function private.hub_workify_record_comment_duplicates_v1(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function private.hub_workify_record_comment_duplicates_v1(uuid,jsonb,text) to service_role;
