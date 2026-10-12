-- Run in a transaction with request.jwt.claim.sub and test.tenant_id set by the test runner.
-- All synthetic batches/rows are rolled back; no production facts survive.
do $test$
declare tenant uuid:=current_setting('test.tenant_id')::uuid; actor uuid:=auth.uid();
 batches uuid[]:=array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
 prefix text:='__workify_guard_test_'||gen_random_uuid()::text; a jsonb;b jsonb;c jsonb;changed jsonb;legacy jsonb;r jsonb;again jsonb;
begin
 insert into public.kpi_import_batches(id,tenant_id,source_type,data_kind,file_name,file_hash,created_by,row_count)
 select id,tenant,'manual_excel','revenue','__transaction_test.xlsx',md5(id::text)||md5(id::text),actor,20 from unnest(batches)id;
 a:=jsonb_build_object('row_number',1,'occurred_on','2026-09-03','amount',100,'quantity',1,'currency','SEK','is_valid',true,'validation_errors','[]'::jsonb,
 'source_data',jsonb_build_object('Ordernummer',prefix||'A','Artikelnummer','100','RegNr','TEST00','Littranummer','test','Kvantitet','1','Enhet','st','Summa','100','Orderstatus','Finished'));
 b:=jsonb_set(jsonb_set(jsonb_set(a,'{source_data,Ordernummer}',to_jsonb(prefix||'B')),'{amount}','200'),' {row_number}'::text[],'3');
 c:=jsonb_set(jsonb_set(jsonb_set(a,'{source_data,Ordernummer}',to_jsonb(prefix||'C')),'{amount}','90'),'{row_number}','4');
 r:=public.hub_kpi_ingest_workify_file_v1(tenant,batches[1],jsonb_build_array(a,jsonb_set(a,'{row_number}','2'),b));
 if (r->>'insertedRows')::int<>3 then raise exception 'Legitimate identical lines were collapsed: %',r;end if;
 r:=public.hub_kpi_ingest_workify_file_v1(tenant,batches[2],jsonb_build_array(jsonb_set(b,'{row_number}','1'),jsonb_set(a,'{row_number}','2'),jsonb_set(a,'{row_number}','3'),c));
 if (r->>'insertedRows')::int<>1 or (r->>'duplicateRowsSkipped')::int<>3 then raise exception 'Overlapping reordered file was not incremental: %',r;end if;
 again:=public.hub_kpi_ingest_workify_file_v1(tenant,batches[2],jsonb_build_array(a));
 if again<>r then raise exception 'Same-batch retry was not idempotent';end if;
 changed:=jsonb_set(a,'{amount}','110');
 r:=public.hub_kpi_ingest_workify_file_v1(tenant,batches[3],jsonb_build_array(changed,jsonb_set(changed,'{row_number}','2'),b,c,jsonb_set(c,'{source_data,Ordernummer}',to_jsonb(prefix||'D'))));
 if r->>'status'<>'blocked_changes' or (r->>'insertedRows')::int<>0 then raise exception 'Edited source became a new income: %',r;end if;
 if exists(select 1 from public.kpi_import_rows where batch_id=batches[3]) then raise exception 'Blocked delivery left partial financial rows';end if;
 if exists(select 1 from public.kpi_import_rows where batch_id=any(batches) and source_fingerprint is not null and external_transaction_id is distinct from source_fingerprint) then raise exception 'Incremental source IDs depend on file row order';end if;
 if (select sum(amount)from public.kpi_import_rows where batch_id=any(batches))<>490 then raise exception 'Repeat/edited delivery changed prior amount';end if;
 r:=public.hub_kpi_ingest_workify_file_v1(tenant,batches[4],jsonb_build_array(a,jsonb_set(a,'{row_number}','2'),jsonb_set(a,'{row_number}','3'),jsonb_set(b,'{row_number}','4'),jsonb_set(c,'{row_number}','5')));
 if (r->>'insertedRows')::int<>1 or (r->>'duplicateRowsSkipped')::int<>4 then raise exception 'A third genuine identical line was lost: %',r;end if;
 legacy:=jsonb_set(jsonb_set(a,'{source_data,Ordernummer}',to_jsonb(prefix||'LEGACY')),'{source_data,Kvantitet}','"1.000,25"');
 insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,amount,quantity,source_data)
 values(tenant,batches[5],1,'revenue','2026-09-03',100,null,legacy->'source_data');
 r:=public.hub_kpi_ingest_workify_file_v1(tenant,batches[6],jsonb_build_array(jsonb_set(legacy,'{quantity}','1000.25')));
 if (r->>'insertedRows')::int<>0 or (r->>'duplicateRowsSkipped')::int<>1 then raise exception 'Legacy row with previously missing mapped quantity duplicated: %',r;end if;
 if has_function_privilege('anon','public.hub_kpi_ingest_workify_file_v1(uuid,uuid,jsonb)','execute') then raise exception 'Anonymous ingestion allowed';end if;
end $test$;
select 'PASS overlap, reordering, multiplicity, atomic edits, retries, legacy locale, anonymous denial' as test;
