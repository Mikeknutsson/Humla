-- Synthetic full-year snapshots: physical repetitions, reordering, new rows,
-- source edits, credits, status advances and retries. No data survives rollback.
begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
set local statement_timeout='120s';
do $$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';actor uuid:=auth.uid();prefix text:='__year_test_'||gen_random_uuid();
 batches uuid[];kind text;bid uuid;r jsonb;a jsonb;b jsonb;c jsonb;d jsonb;changed jsonb;payload jsonb;money numeric;
begin
 foreach kind in array array['revenue','cost']loop
 batches:=array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
 insert into public.kpi_import_batches(id,tenant_id,source_type,data_kind,file_name,file_hash,created_by,period_start,period_end)
 select x,t,'manual_excel',kind,'synthetic_full_year.xlsx',md5(x::text)||md5(x::text),actor,'2026-09-01','2027-08-31'from unnest(batches)x;
 a:=jsonb_build_object('row_number',1,'data_kind',kind,'occurred_on','2026-09-03','amount',100,'quantity',1,'currency','SEK','is_valid',true,'validation_errors','[]'::jsonb,
 'source_data',case when kind='revenue'then jsonb_build_object('Ordernummer',prefix||'A','Artikelnummer','100','RegNr','TEST00','Kvantitet','1','Enhet','st','Summa','100','Orderstatus','Reported')
 else jsonb_build_object('Verifikation nr',prefix||'A','Projektnr','__synthetic_project','Konto','5610','Verifikationstext','Synthetic cost','Nettobelopp','100')end);
 b:=jsonb_set(jsonb_set(a,'{row_number}','3'),'{amount}','200');
 c:=jsonb_set(jsonb_set(a,'{row_number}','4'),'{amount}','90');
 d:=jsonb_set(jsonb_set(a,'{row_number}','5'),'{amount}','80');
 b:=jsonb_set(b,case when kind='revenue'then '{source_data,Ordernummer}'else '{source_data,Verifikation nr}'end::text[],to_jsonb(prefix||'B'));
 c:=jsonb_set(c,case when kind='revenue'then '{source_data,Ordernummer}'else '{source_data,Verifikation nr}'end::text[],to_jsonb(prefix||'C'));
 d:=jsonb_set(d,case when kind='revenue'then '{source_data,Ordernummer}'else '{source_data,Verifikation nr}'end::text[],to_jsonb(prefix||'D'));
 payload:=jsonb_build_array(a,jsonb_set(a,'{row_number}','2'),b);
 r:=case when kind='revenue'then public.hub_kpi_ingest_workify_file_v1(t,batches[1],payload)else public.hub_kpi_ingest_cost_file_v1(t,batches[1],payload)end;
 if(r->>'insertedRows')::int<>3 then raise exception '%: physical identical lines were collapsed: %',kind,r;end if;
 payload:=jsonb_build_array(jsonb_set(b,'{row_number}','1'),jsonb_set(a,'{row_number}','2'),jsonb_set(a,'{row_number}','3'),c);
 r:=case when kind='revenue'then public.hub_kpi_ingest_workify_file_v1(t,batches[2],payload)else public.hub_kpi_ingest_cost_file_v1(t,batches[2],payload)end;
 if(r->>'insertedRows')::int<>1 or(r->>'duplicateRowsSkipped')::int<>3 then raise exception '%: full-year reorder doubled old rows: %',kind,r;end if;
 changed:=jsonb_set(a,'{amount}','110');
 payload:=jsonb_build_array(changed,jsonb_set(changed,'{row_number}','2'),b,c,d);
 r:=case when kind='revenue'then public.hub_kpi_ingest_workify_file_v1(t,batches[3],payload)else public.hub_kpi_ingest_cost_file_v1(t,batches[3],payload)end;
 if(r->>'insertedRows')::int<>1 or(r->>'changedRows')::int<>2 or r->>'status'<>'needs_review'then raise exception '%: edited document blocked independent new rows or duplicated the revision: %',kind,r;end if;
 if(select sum(amount)from public.kpi_import_rows where batch_id=any(batches))<>570 then raise exception '%: edited source changed authoritative money',kind;end if;
 if kind='revenue'then
 r:=public.hub_kpi_resolve_workify_import_v1(t,batches[3]);
 if r->>'status'<>'needs_review' or(select status from public.kpi_import_batches where id=batches[3])<>'needs_review'then raise exception 'Mapping resolution cleared source-revision review';end if;
 end if;
 r:=case when kind='revenue'then public.hub_kpi_ingest_workify_file_v1(t,batches[3],payload)else public.hub_kpi_ingest_cost_file_v1(t,batches[3],payload)end;
 if(r->>'insertedRows')::int<>1 then raise exception '%: retry response changed',kind;end if;
 payload:=jsonb_build_array(a,jsonb_set(a,'{row_number}','2'),jsonb_set(a,'{row_number}','6'),b,c,d);
 r:=case when kind='revenue'then public.hub_kpi_ingest_workify_file_v1(t,batches[4],payload)else public.hub_kpi_ingest_cost_file_v1(t,batches[4],payload)end;
 if(r->>'insertedRows')::int<>1 then raise exception '%: a new genuine repeated source line was lost: %',kind,r;end if;
 if(select sum(amount)from public.kpi_import_rows where batch_id=any(batches))<>670 then raise exception '%: multiplicity or retry changed money',kind;end if;
 if kind='cost'then
 payload:=jsonb_build_array(jsonb_set(jsonb_set(d,'{amount}','-50'),'{source_data,Verifikation nr}',to_jsonb(prefix||'CREDIT')));
 r:=public.hub_kpi_ingest_cost_file_v1(t,batches[5],payload);
 if(r->>'insertedRows')::int<>1 or(select sum(amount)from public.kpi_import_rows where batch_id=any(batches))<>620 then raise exception 'Credit row lost';end if;
 else
 payload:=jsonb_build_array(jsonb_set(a,'{source_data,Orderstatus}','"Invoiced"'),jsonb_set(jsonb_set(a,'{row_number}','2'),'{source_data,Orderstatus}','"Invoiced"'),jsonb_set(jsonb_set(a,'{row_number}','6'),'{source_data,Orderstatus}','"Invoiced"'),b,c,d);
 r:=public.hub_kpi_ingest_workify_file_v1(t,batches[5],payload);
 if(r->>'insertedRows')::int<>0 or(select sum(amount)from public.kpi_import_rows where batch_id=any(batches))<>670 then raise exception 'Status update became new revenue';end if;
 end if;
 end loop;
end$$;
select 'PASS full-year reimport, changed-document isolation, new rows, multiplicity, retry, status and credit'as result;
rollback;
