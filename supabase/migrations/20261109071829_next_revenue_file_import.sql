create function public.hub_kpi_ingest_next_revenue_file_v1(
 p_tenant_id uuid, p_batch_id uuid, p_rows jsonb
) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='60s' set jit=off
as $function$
declare
 previous_result jsonb;
 batch_status text;
 received integer;
 zero_count integer;
 inserted_count integer;
 result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then
  raise exception 'KPI-administratör krävs' using errcode='42501';
 end if;
 if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Ogiltig NeXT-leverans';end if;
 received:=jsonb_array_length(p_rows);
 if received not between 1 and 50000 then raise exception 'Ogiltigt antal NeXT-rader';end if;

 perform pg_advisory_xact_lock(hashtextextended('next-revenue-file:'||p_tenant_id::text,0));
 select b.status,b.provenance->'next_revenue_ingest' into batch_status,previous_result
 from public.kpi_import_batches b
 where b.tenant_id=p_tenant_id and b.id=p_batch_id and b.data_kind='revenue'
 for update;
 if not found then raise exception 'Importen saknas';end if;
 if previous_result is not null then return previous_result;end if;
 if batch_status<>'processing' then raise exception 'Importen är inte öppen';end if;

 if exists (
  select 1 from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows) r
  where r.data_kind is distinct from 'revenue' or r.is_valid is distinct from true
   or r.row_number is null or r.row_number<1
   or not private.hub_is_next_ledger_revenue_v1(r.source_data)
   or r.account is null or r.account !~ '^3[0-9]{3}$'
   or r.account is distinct from trim(r.source_data->>'Konto')
   or r.project_reference is distinct from trim(r.source_data->>'Projektnr')
   or r.occurred_on is null or r.amount is null or r.amount::text in ('NaN','Infinity','-Infinity')
 ) then raise exception 'Ogiltig bokförd intäktsrad från NeXT';end if;

 select count(*) into zero_count from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows) r where r.amount=0;
 with incoming as materialized (
  select r.*, private.hub_economic_key_v2('revenue',r.occurred_on,r.amount,null,'SEK',r.source_data,'') fingerprint
  from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows) r where r.amount<>0
 ), numbered as (
  select i.*,row_number() over(partition by fingerprint order by row_number) occurrence from incoming i
 ), prior_batches as (
  select private.hub_economic_key_v2('revenue',r.occurred_on,r.amount,null,'SEK',r.source_data,'') fingerprint,
   r.batch_id,count(*) copies
  from public.kpi_import_rows r
  where r.tenant_id=p_tenant_id and r.data_kind='revenue' and r.is_valid
   and r.occurred_on between (select min(occurred_on) from incoming) and (select max(occurred_on) from incoming)
   and private.hub_is_next_ledger_revenue_v1(r.source_data)
   and not coalesce(r.validation_errors,'[]') ? 'Importen återtagen eller ersatt; ingår inte i beräkningar'
  group by 1,2
 ), known as (
  select fingerprint,max(copies) copies from prior_batches group by fingerprint
 ), saved as (
  insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,
   project_reference,cost_center,account,description,amount,currency,is_valid,validation_errors,
   source_data,source_system,external_transaction_id,source_fingerprint)
  select p_tenant_id,p_batch_id,n.row_number,'revenue',n.occurred_on,
   n.project_reference,n.cost_center,n.account,n.description,n.amount,'SEK',true,'[]',
   n.source_data,'next_file','next-revenue-v1:'||n.fingerprint||':'||n.occurrence,
   'next-revenue-v1:'||n.fingerprint||':'||n.occurrence
  from numbered n left join known k using(fingerprint)
  where n.occurrence>coalesce(k.copies,0)
  on conflict(tenant_id,data_kind,source_fingerprint) where source_fingerprint is not null do nothing
  returning id
 )
 select count(*) into inserted_count from saved;

 result:=jsonb_build_object('status','completed','receivedRows',received,'insertedRows',inserted_count,
  'duplicateRowsSkipped',received-zero_count-inserted_count,'ignoredZeroRows',zero_count,
  'validRows',inserted_count,'invalidRows',0);
 update public.kpi_import_batches
 set status='completed',row_count=inserted_count,valid_row_count=inserted_count,invalid_row_count=0,
  completed_at=now(),provenance=coalesce(provenance,'{}')||jsonb_build_object('next_revenue_ingest',result)
 where tenant_id=p_tenant_id and id=p_batch_id;
 return result;
end
$function$;
revoke all on function public.hub_kpi_ingest_next_revenue_file_v1(uuid,uuid,jsonb) from public,anon;
grant execute on function public.hub_kpi_ingest_next_revenue_file_v1(uuid,uuid,jsonb) to authenticated;
