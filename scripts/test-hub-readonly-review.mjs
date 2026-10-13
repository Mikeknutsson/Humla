import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite} = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const db = new PGlite();
await db.exec(`create schema private; create schema auth;
create role anon; create role authenticated; create role service_role;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
create function public.hub_has_permission(uuid,text) returns boolean language sql as $$select $1='20000000-0000-0000-0000-000000000001'::uuid and $2='kpi.read'$$;
create table public.kpi_import_batches(id uuid primary key,tenant_id uuid,status text,file_name text);
create table public.kpi_import_rows(id uuid primary key default gen_random_uuid(),tenant_id uuid,batch_id uuid,row_number int,data_kind text,
 occurred_on date,amount numeric,quantity numeric,currency text,source_data jsonb,project_reference text,is_valid boolean,validation_errors jsonb,created_at timestamptz default now());
create table public.hub_cost_allocation_rules(tenant_id uuid,enabled boolean);
create table public.hub_identity_keys(tenant_id uuid,identity_type text,identity_value text,object_id uuid,confidence numeric);
create table public.hub_objects(id uuid primary key,tenant_id uuid,data jsonb);
create table public.kpi_transpa_time_facts(tenant_id uuid,employee_id text,work_date date,time_report_id text,transpa_vehicle_ids jsonb);
-- Existing candidate-key dependency: review functions must never treat a collision as proof.
create function private.hub_economic_key_v2(text,date,numeric,numeric,text,jsonb,text) returns text language sql immutable as $$select md5(jsonb_build_array($1,$2,$3,$4,$5,$6)::text)$$;`);
await db.exec(await readFile(new URL('../supabase/migrations/20261013133745_hub_readonly_transaction_review.sql',import.meta.url),'utf8'));
const t='20000000-0000-0000-0000-000000000001',other='20000000-0000-0000-0000-000000000002';
const batch='30000000-0000-0000-0000-000000000001',batch2='30000000-0000-0000-0000-000000000002';
await db.query("insert into public.kpi_import_batches values($1,$2,'completed','first'),($3,$2,'failed','second')",[batch,t,batch2]);
await db.query(`insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,amount,currency,source_data,is_valid)
 select $1::uuid,$2::uuid,n,'cost','2026-10-01',100.01,'SEK','{}',true from generate_series(1,205)n`,[t,batch]);
await db.query(`insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,amount,currency,source_data,is_valid)
 values($1,$2,1,'cost','2026-10-01',100.01,'SEK','{}',true),($1,$2,2,'cost','2026-10-01',-10.01,'SEK','{}',false),($1,$2,3,'cost',null,0,'SEK','{}',false)`,[t,batch2]);
await db.query(`insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,amount,currency,source_data,is_valid)
 values($1,$2,999,'cost','2026-10-01',999999,'SEK','{}',true)`,[other,batch]);
const before=(await db.query('select md5(jsonb_agg(r order by id)::text) hash from public.kpi_import_rows r')).rows[0].hash;
await assert.rejects(db.query('select public.hub_cost_review_v1($1,0)',[t]),/KPI access required/);
await db.exec("set test.actor='10000000-0000-0000-0000-000000000001'");
await assert.rejects(db.query('select public.hub_cost_review_v1($1,0)',[other]),/KPI access required/);
await assert.rejects(db.query('select public.hub_cost_review_v1($1,-1)',[t]),/Invalid page/);
const report=(await db.query('select public.hub_cost_review_v1($1,0) r',[t])).rows[0].r;
assert.equal(report.totalRows,208);assert.equal(report.reviewRows,207);assert.equal(report.invalidRows,1);
assert.equal(report.possibleDuplicateRows,1);assert.equal(report.verifiedUniqueRows,0);assert.equal(report.verifiedDuplicateRows,0);
assert.equal(report.partitionDifferenceRows,0);assert.equal(report.financialReconciliationDifference,null);
assert.equal(report.items.length,100);assert.equal(report.totals.find(t=>t.review_state==='review_required').amount,'20592.05');
const last=(await db.query('select public.hub_cost_review_v1($1,2) r',[t])).rows[0].r;
assert.equal(last.totalRows,208);assert.equal(last.items.length,8);
const person='40000000-0000-0000-0000-000000000001',vehicle='50000000-0000-0000-0000-000000000001';
await db.query(`insert into public.hub_identity_keys values($1,'transpa_employee_id','p1',$2,1),($1,'transpa_vehicle_id','v1',$3,1)`,[t,person,vehicle]);
await db.query(`insert into public.kpi_transpa_time_facts values($1,'p1','2026-10-01','r1','["v1"]'),($1,'p1','2026-10-02','r2','["v1","unknown"]'),($1,'p2','2026-10-01','r3','["v1"]')`,[t]);
const days=(await db.query('select public.hub_transpa_day_review_v1($1,0) r',[t])).rows[0].r;
assert.equal(days.totalRows,3);assert.equal(days.evidenceRows,1);assert.equal(days.reviewRows,2);assert.equal(days.sourceReports,3);
assert.equal(days.items.find(x=>x.work_date==='2026-10-02').vehicle_object_id,null);
const after=(await db.query('select md5(jsonb_agg(r order by id)::text) hash from public.kpi_import_rows r')).rows[0].hash;
assert.equal(before,after);
assert.equal((await db.query("select has_function_privilege('anon','public.hub_cost_review_v1(uuid,integer)','execute') allowed")).rows[0].allowed,false);
console.log('PASS: tenant/auth isolation, full-history totals, pagination, credits, possible duplicates, missing identities, dated evidence and immutable originals');
await db.close();
