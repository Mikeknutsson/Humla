import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite}=await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const {pgcrypto}=await import(process.env.PGLITE_CRYPTO_MODULE ?? '@electric-sql/pglite/contrib/pgcrypto');
const db=new PGlite({extensions:{pgcrypto}});
// Isolated schema only: no production connection or real user impersonation.
await db.exec(`create schema private; create schema auth; create schema extensions;
create role anon; create role authenticated; create role service_role;
create function auth.uid() returns uuid language sql as $$select '10000000-0000-0000-0000-000000000001'::uuid$$;
create function public.hub_has_permission(uuid,text) returns boolean language sql as $$select true$$;
create extension pgcrypto with schema extensions;
create table public.hub_tenants(id uuid primary key);
create table public.hub_objects(id uuid primary key,tenant_id uuid);
create table public.kpi_import_batches(id uuid primary key,tenant_id uuid,data_kind text,provenance jsonb default '{}',status text,
 row_count int,valid_row_count int,invalid_row_count int,completed_at timestamptz,error_summary jsonb);
create table public.kpi_import_rows(id uuid primary key default gen_random_uuid(),tenant_id uuid,batch_id uuid,row_number int,
 data_kind text,occurred_on date,vehicle_object_id uuid,vehicle_registration text,employee_object_id uuid,employee_number text,
 project_reference text,cost_center text,account text,description text,quantity numeric,amount numeric,currency text,
 available_hours numeric,occupied_hours numeric,paid_hours numeric,billable_hours numeric,is_valid boolean,
 validation_errors jsonb,source_data jsonb,allocation jsonb,source_system text,external_transaction_id text,source_fingerprint text,
 created_at timestamptz default now());
create unique index on public.kpi_import_rows(tenant_id,data_kind,source_fingerprint) where source_fingerprint is not null;
insert into public.hub_tenants values('20000000-0000-0000-0000-000000000001');`);
const v1=await readFile(new URL('../supabase/migrations/20261012110229_workify_incremental_file_guard.sql',import.meta.url),'utf8');
await db.exec(v1.slice(0,v1.indexOf('drop index')));
const migration=await readFile(new URL('../supabase/migrations/20261013082221_workify_row_identity_and_status_history.sql',import.meta.url),'utf8');
await db.exec(migration);
const reconciliation=await readFile(new URL('../supabase/migrations/20261013082933_workify_historical_row_reconciliation.sql',import.meta.url),'utf8');
await db.exec(reconciliation);
const immutable=await readFile(new URL('../supabase/migrations/20261013083531_workify_immutable_observation_projection.sql',import.meta.url),'utf8');
await db.exec(immutable);
await db.exec(`create function private.original_guard() returns trigger language plpgsql as $$begin
 if new.source_data is distinct from old.source_data then raise exception 'Original must not change'; end if;return new;end$$;
 create trigger original_guard before update on public.kpi_import_rows for each row execute function private.original_guard();`);
const tenant='20000000-0000-0000-0000-000000000001';
let sequence=0;
const row=(status='Reported',amount=100,extra={})=>({row_number:1,occurred_on:'2026-09-01',amount,quantity:1,is_valid:true,
 source_data:{Ordernummer:'TEST-1',Artikelnummer:'A',Artikeldatum:'2026-09-01',Kvantitet:'1',Summa:String(amount),Orderstatus:status,...extra}});
async function ingest(rows,batch){
 const id=batch ?? `30000000-0000-0000-0000-${String(++sequence).padStart(12,'0')}`;
 if(!batch)await db.query('insert into public.kpi_import_batches(id,tenant_id,data_kind)values($1,$2,$3)',[id,tenant,'revenue']);
 const {rows:result}=await db.query('select public.hub_kpi_ingest_workify_file_v1($1,$2,$3::jsonb) result',[tenant,id,JSON.stringify(rows)]);
 return {...result[0].result,batch:id};
}
async function total(){return (await db.query('select count(*)::int rows,sum(amount)::text amount from public.kpi_import_rows')).rows[0];}
const first=await ingest([row()]);assert.equal(first.insertedRows,1);
for(const status of ['ReadyForInvoicing','Invoiced','Reported']){
 const result=await ingest([row(status,100,status==='Invoiced'?{Fakturerad:'2026-10-13'}:{})]);
 assert.equal(result.insertedRows,0);assert.deepEqual(await total(),{rows:1,amount:'100'});
}
assert.equal((await db.query("select private.hub_workify_effective_source_v1(id,source_data)->>'Orderstatus' status from public.kpi_import_rows")).rows[0].status,'Invoiced');
assert.equal((await ingest([row()],first.batch)).insertedRows,1); // Cached result, not another insert.
assert.deepEqual(await total(),{rows:1,amount:'100'});
const second={...row('Invoiced'),row_number:8};
assert.equal((await ingest([row('Invoiced'),second])).insertedRows,1);
assert.equal((await ingest([second,row('Invoiced')])).insertedRows,0);
assert.deepEqual(await total(),{rows:2,amount:'200'});
const third={...row('Invoiced'),row_number:22};
assert.equal((await ingest([row('Invoiced'),second,third])).insertedRows,1);
assert.equal((await ingest([third,second,row('Invoiced')])).insertedRows,0);
assert.deepEqual(await total(),{rows:3,amount:'300'});
assert.equal((await ingest([row('Invoiced',150)])).status,'blocked_changes');
assert.equal((await ingest([row('Invoiced',100,{RegNr:'ALD61D'})])).status,'blocked_changes');
assert.equal((await ingest([row('Invoiced',100,{Artikelnummer:'B'})])).status,'blocked_changes');
assert.deepEqual(await total(),{rows:3,amount:'300'});
assert.equal((await ingest([row('Reported')])).insertedRows,0); // Partial older export never removes rows.
const credit=row('Invoiced',-25,{Ordernummer:'CREDIT-1'});
assert.equal((await ingest([credit])).insertedRows,1);
assert.equal((await ingest([credit])).insertedRows,0);
assert.deepEqual(await total(),{rows:4,amount:'275'});
assert.equal((await ingest([row('Reported',0,{Ordernummer:'ZERO'})])).ignoredZeroRows,1);
assert.equal((await ingest([row('Reported',100,{Ordernummer:''})])).status,'blocked_changes');
// A receipt/reference difference is real source content, not silently discarded.
const newOrder=[row('Reported',50,{Ordernummer:'TWO-RECEIPTS',ExterntDokumentnummer:'A'}),
 {...row('Reported',50,{Ordernummer:'TWO-RECEIPTS',ExterntDokumentnummer:'B'}),row_number:2}];
assert.equal((await ingest(newOrder)).insertedRows,2);
assert.equal((await ingest(newOrder.reverse())).insertedRows,0);
assert.equal((await db.query("select count(*)::int n from private.hub_workify_row_observations where decision='blocked'")).rows[0].n,4);
assert.equal((await db.query("select count(*)::int n from private.hub_workify_row_observations where decision<>'blocked' and canonical_row_id is null")).rows[0].n,0);
const scope=await readFile(new URL('../supabase/tests/workify_pending_status_scope.sql',import.meta.url),'utf8');
await db.exec(scope.slice(0,scope.indexOf('do $migration$')));
for(const status of ['ReadyForInvoicing','Invoiced','Reported']){
 assert.equal((await db.query('select private.hub_workify_revenue_in_scope_v1($1::jsonb) ok',[JSON.stringify({Ordernummer:'1',Orderstatus:status})])).rows[0].ok,true);
}
for(const status of ['Assigned','Done',null]){
 assert.equal((await db.query('select private.hub_workify_revenue_in_scope_v1($1::jsonb) ok',[JSON.stringify({Ordernummer:'1',Orderstatus:status})])).rows[0].ok,false);
}
assert.equal((await db.query("select private.hub_workify_revenue_in_scope_v1('{\"Nettobelopp\":100}') ok")).rows[0].ok,true);
for(const status of ['Reported','ReadyForInvoicing','Invoiced']){
 const batch=`40000000-0000-0000-0000-${String(++sequence).padStart(12,'0')}`;
 await db.query('insert into public.kpi_import_batches(id,tenant_id,data_kind)values($1,$2,$3)',[batch,tenant,'revenue']);
 for(const rn of [1,2])await db.query(`insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,amount,quantity,is_valid,source_data)
 values($1,$2,$3,'revenue','2026-09-01',200,1,true,$4::jsonb)`,[tenant,batch,rn,JSON.stringify(row(status,200,{Ordernummer:'HISTORICAL',ExterntDokumentnummer:status==='Invoiced'?'INVOICE-42':''}).source_data)]);
}
const fixed=(await db.query('select private.hub_workify_reconcile_history_v2($1) result',[tenant])).rows[0].result;
assert.equal(fixed.duplicate_rows,4);assert.equal(fixed.duplicate_amount,800);
assert.deepEqual((await db.query("select count(*)::int n,sum(amount)::text total from public.kpi_import_rows where is_valid and source_data->>'Ordernummer'='HISTORICAL' and not exists(select 1 from private.hub_workify_reconciliation_audit a where a.row_id=kpi_import_rows.id and a.action='duplicate')")).rows[0],{n:2,total:'400'});
assert.equal((await db.query('select private.hub_workify_reconcile_history_v2($1) result',[tenant])).rows[0].result.duplicate_rows,0);
assert.equal((await ingest([row('Invoiced',200,{Ordernummer:'HISTORICAL',ExterntDokumentnummer:'INVOICE-42'}),{...row('Invoiced',200,{Ordernummer:'HISTORICAL',ExterntDokumentnummer:'INVOICE-42'}),row_number:2}])).insertedRows,0);
console.log('PASS: status progression, older reimport, idempotency, identical real rows, incremental multiplicity, reordered rows, changed amount/vehicle/article, partial exports, credits, zero rows, missing identity, distinct receipts, audit trail');
console.log('PASS: three eligible statuses, other Workify statuses excluded, NEXT unaffected, historical duplicates and invoice-reference enrichment, reconciliation idempotency, reimport after repair');
await db.close();
