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
await db.exec(`alter table public.kpi_import_batches add column file_name text;
create table private.hub_kpi_report_state(tenant_id uuid primary key,active_generation uuid);
create table private.hub_kpi_prepared_facts(tenant_id uuid,generation_id uuid,fact_id text,kind text,amount numeric);
create or replace function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
create or replace function public.hub_has_permission(uuid,text) returns boolean language sql as $$select $1='20000000-0000-0000-0000-000000000002'::uuid and $2='kpi.read'$$;
insert into public.hub_tenants values('20000000-0000-0000-0000-000000000002');`);
await db.exec(await readFile(new URL('../supabase/migrations/20261013142229_hub_workify_review_projection.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../supabase/migrations/20261013142407_hub_workify_zero_row_review.sql',import.meta.url),'utf8'));
const tenant='20000000-0000-0000-0000-000000000002',other='20000000-0000-0000-0000-000000000001';
const generation='60000000-0000-0000-0000-000000000001';
const a='70000000-0000-0000-0000-000000000001',b='70000000-0000-0000-0000-000000000002';
await db.query("insert into public.kpi_import_batches(id,tenant_id,file_name) values($1,$2,'original'),($3,$2,'new-status')",[a,tenant,b]);
await db.query('insert into private.hub_kpi_report_state values($1,$2)',[tenant,generation]);
let sequence=0;
async function add(order,status,amount,{batch=a,valid=true,errors=[],doc='',currency='SEK',prepared=null}={}) {
 const id=`80000000-0000-0000-0000-${String(++sequence).padStart(12,'0')}`;
 const source={Ordernummer:order,Artikelnummer:'ART',Orderstatus:status,ExterntDokumentnummer:doc,Summa:String(amount),Kvantitet:'1'};
 await db.query(`insert into public.kpi_import_rows(id,tenant_id,batch_id,row_number,data_kind,occurred_on,amount,quantity,currency,is_valid,validation_errors,source_data,created_at)
 values($1,$2,$3,$4,'revenue','2026-09-01',$5,1,$6,$7,$8,$9,$10)`,[id,tenant,batch,sequence,amount,currency,valid,JSON.stringify(errors),JSON.stringify(source),batch===a?'2026-09-01':'2026-09-02']);
 if(prepared!==null){
  await db.query("insert into private.hub_kpi_prepared_facts values($1,$2,$3,'revenue',$4),($1,$2,$5,'revenue',20)",[tenant,generation,id,prepared,id+':material']);
 }
 return id;
}
const originals=[];
for(let i=0;i<2;i++) originals.push(await add('PROGRESSION','Reported',100,{prepared:100}));
for(let i=0;i<2;i++) await add('PROGRESSION','Invoiced',100,{batch:b,doc:'INV1',prepared:100});
await add('PROGRESSION','Reported',100,{valid:false,errors:['Unresolved financial validation']});
await add('CREDIT','ReadyForInvoicing',-10);
await add('MAPPING','Reported',25,{valid:false,errors:['Workify-artikeln ska till fordon: registreringsnummer behöver mappas']});
await add('OPEN','Assigned',40,{prepared:40});
await add('ZERO','Invoiced',0);
await add('PROGRESSION','Reported',100,{currency:'EUR'});
await add('','Reported',70);
await add('WITHDRAWN','Invoiced',11,{errors:['Importen återtagen eller ersatt; ingår inte i beräkningar']});
const zeroId=await add('ZERO-NO-DATE','Reported',0);
await db.query('update public.kpi_import_rows set occurred_on=null where id=$1',[zeroId]);
const before=(await db.query('select md5(jsonb_agg(r order by id)::text) hash from public.kpi_import_rows r')).rows[0].hash;
await assert.rejects(db.query('select public.hub_workify_review_v1($1,0,\'all\')',[tenant]),/KPI access required/);
await db.exec("set test.actor='10000000-0000-0000-0000-000000000001'");
await assert.rejects(db.query('select public.hub_workify_review_v1($1,0,\'all\')',[other]),/KPI access required/);
await assert.rejects(db.query('select public.hub_workify_review_v1($1,-1,\'all\')',[tenant]),/Invalid page/);
const report=(await db.query('select public.hub_workify_review_v1($1,0,\'all\') r',[tenant])).rows[0].r;
assert.equal(report.totalRows,13);
const state=(s,c='SEK')=>report.totals.find(t=>t.review_state===s&&t.currency===c);
assert.equal(state('candidate_include').rows,4); // Two genuine occurrences, credit, mapping-only row.
assert.equal(state('candidate_include').source_amount,'215');
assert.equal(state('candidate_include').current_prepared_amount,'240'); // Both material components included.
assert.equal(state('candidate_include').allocation_review_rows,1);
assert.equal(state('candidate_include').missing_from_prepared_rows,2);
assert.equal(state('candidate_duplicate').rows,2);
assert.equal(state('candidate_duplicate').current_prepared_amount,'240');
assert.equal(state('excluded_status').rows,1);assert.equal(state('excluded_status').current_prepared_amount,'60');
assert.equal(state('candidate_include','EUR').rows,1);
assert.equal(state('review_required').rows,2);assert.equal(state('ignored_zero').rows,2);assert.equal(state('excluded_withdrawn').rows,1);
assert.ok(report.items.filter(r=>originals.includes(r.row_id)).every(r=>r.effective_status==='Invoiced'&&r.original_status==='Reported'));
assert.ok(report.controls.every(c=>Number(c.partition_difference)===0));
assert.equal(report.months.find(m=>m.currency==='SEK').current_amount,'540');
const selected=(await db.query('select public.hub_workify_review_v1($1,0,\'candidate_duplicate\') r',[tenant])).rows[0].r;
assert.equal(selected.selectedRows,2);assert.equal(selected.items.length,2);assert.equal(selected.totalRows,13);
assert.equal((await db.query('select md5(jsonb_agg(r order by id)::text) hash from public.kpi_import_rows r')).rows[0].hash,before);
assert.equal((await db.query("select has_function_privilege('anon','public.hub_workify_review_v1(uuid,integer,text)','execute') allowed")).rows[0].allowed,false);
console.log('PASS: all-source accounting, three statuses, identical genuine occurrences, financial/withdrawal separation, mapping-only rows, credits, currency isolation, material components, original preservation and access control');

const activation=await readFile(new URL('../supabase/migrations/20261013145857_hub_workify_approved_financial_scope.sql',import.meta.url),'utf8');
await db.exec(activation.slice(0,activation.indexOf('do $migration$')));
await db.exec(`alter table private.hub_kpi_prepared_facts add column original jsonb default '{}',add column occurred_on date,add column category text,add column project text,add column vehicle text,add column unit_id uuid,add column unit_name text,add column business_group text,add column source text,add column cost_center text;`);
const auditMigration=await readFile(new URL('../supabase/migrations/20261013145902_hub_workify_activation_audit.sql',import.meta.url),'utf8');
await db.exec(auditMigration.slice(0,auditMigration.indexOf('do $migration$')));
await db.exec(await readFile(new URL('../supabase/migrations/20261013150826_hub_workify_activation_batches.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../supabase/migrations/20261013152752_hub_workify_cost_comparison_details.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../supabase/migrations/20261013161133_hub_workify_approved_group_changes.sql',import.meta.url),'utf8'));
const controls=(await db.query(`select jsonb_agg(to_jsonb(t)order by currency,review_state) controls from(
 select currency,review_state,count(*) rows,sum(amount)::text amount from private.hub_workify_review_rows_v1($1)group by 1,2)t`,[tenant])).rows[0].controls;
await assert.rejects(db.query('select private.hub_workify_apply_approved_review_v1($1,$2,$3)',[tenant,JSON.stringify([]),'Test approval']),/Approved source scope changed/);
const staged=(await db.query('select private.hub_workify_apply_approved_review_v1($1,$2,$3) r',[tenant,JSON.stringify(controls),'Local isolated test approval'])).rows[0].r;
let remaining=staged.stagedDecisions;
while(remaining>0) remaining=(await db.query('select private.hub_workify_apply_activation_chunk_v1($1,2) r',[staged.runId])).rows[0].r.remainingDecisions;
const included=(await db.query(`select currency,count(*) rows,sum(amount)::text amount from public.kpi_import_rows x
 where tenant_id=$1 and private.hub_kpi_import_row_in_scope_v2(x.id,x.data_kind,x.occurred_on,x.amount,x.is_valid,x.validation_errors,x.source_data)
 group by currency order by currency`,[tenant])).rows;
assert.equal(included.find(x=>x.currency==='SEK').rows,4);
assert.equal(included.find(x=>x.currency==='SEK').amount,'215');
assert.equal(included.find(x=>x.currency==='EUR').amount,'100');
const mapping=(await db.query(`select private.hub_workify_reporting_source_v1(id,source_data,is_valid) data
 from public.kpi_import_rows where source_data->>'Ordernummer'='MAPPING'`)).rows[0].data;
assert.equal(mapping._humla_allocation_review,true);
assert.equal((await db.query("select private.hub_kpi_import_row_in_scope_v2(gen_random_uuid(),'revenue','2026-09-01',500,true,'[]','{\"Konto\":\"3000\"}') ok")).rows[0].ok,true);
assert.equal((await db.query('select md5(jsonb_agg(r order by id)::text) hash from public.kpi_import_rows r')).rows[0].hash,before);
console.log('PASS: activated shared predicate retains all seven-case equivalents, scopes statuses, preserves credits and NEXT revenues, and flags uncertain allocations');

const t3='20000000-0000-0000-0000-000000000003',g3='60000000-0000-0000-0000-000000000003';
await db.query('insert into public.hub_tenants values($1)',[t3]);
await db.query('insert into private.hub_kpi_report_state values($1,$2)',[t3,generation]);
const id1='90000000-0000-0000-0000-000000000001',id2='90000000-0000-0000-0000-000000000002';
await db.query(`insert into public.kpi_import_rows(id,tenant_id,batch_id,row_number,data_kind,occurred_on,amount,currency,is_valid,validation_errors,source_data)
 values($1,$2,$3,1,'revenue','2026-09-01',100,'SEK',true,'[]','{"Ordernummer":"A","Artikelnummer":"A","Orderstatus":"Reported"}'),
 ($4,$2,$3,2,'revenue','2026-09-01',25,'SEK',false,'["Workify-artikeln ska till fordon: registreringsnummer behöver mappas"]','{"Ordernummer":"B","Artikelnummer":"B","Orderstatus":"Reported"}')`,[id1,t3,a,id2]);
const controls3=(await db.query(`select jsonb_agg(to_jsonb(t)order by currency,review_state) controls from(
 select currency,review_state,count(*) rows,sum(amount)::text amount from private.hub_workify_review_rows_v1($1)group by 1,2)t`,[t3])).rows[0].controls;
await db.query('select private.hub_workify_apply_approved_review_v1($1,$2,$3)',[t3,JSON.stringify(controls3),'Local isolated test approval']);
await db.query(`insert into private.hub_kpi_prepared_facts(tenant_id,generation_id,fact_id,kind,amount,original)
 values($1,$2,$3,'revenue',80,'{"Ordernummer":"A"}'),($1,$2,$4,'revenue',20,'{"Ordernummer":"A"}'),($1,$2,$5,'revenue',26,'{"Ordernummer":"B","_humla_allocation_review":true}'),
 ($1,$6,'next-cost','cost',80,'{}'),($1,$2,'next-cost','cost',80,'{}')`,[t3,g3,id1,id1+':material',id2,generation]);
await assert.rejects(db.query('select private.hub_workify_validate_approved_generation_v1($1,$2)',[t3,g3]),/Workify generation differs/);
await db.query("update private.hub_kpi_prepared_facts set amount=25,vehicle='UNVERIFIED' where fact_id=$1 and tenant_id=$2",[id2,t3]);
await assert.rejects(db.query('select private.hub_workify_validate_approved_generation_v1($1,$2)',[t3,g3]),/Uncertain Workify row was allocated/);
await db.query('update private.hub_kpi_prepared_facts set vehicle=null where fact_id=$1 and tenant_id=$2',[id2,t3]);
await db.query("update private.hub_kpi_prepared_facts set amount=81 where fact_id='next-cost' and tenant_id=$1 and generation_id=$2",[t3,g3]);
await assert.rejects(db.query('select private.hub_workify_validate_approved_generation_v1($1,$2)',[t3,g3]),/Existing cost split changed/);
await db.query("update private.hub_kpi_prepared_facts set amount=80 where fact_id='next-cost' and tenant_id=$1 and generation_id=$2",[t3,g3]);
await db.query("update private.hub_kpi_prepared_facts set business_group=case when generation_id=$2 then 'New group' else 'Old group' end where fact_id='next-cost' and tenant_id=$1",[t3,g3]);
await assert.rejects(db.query('select private.hub_workify_validate_approved_generation_v1($1,$2)',[t3,g3]),/Existing cost split changed/);
await db.query("insert into private.hub_workify_approved_cost_groups(run_id,tenant_id,fact_id,old_group,new_group,approval_reference) select id,tenant_id,'next-cost','Old group','New group','Isolated test approval' from private.hub_workify_activation_runs where tenant_id=$1",[t3]);
await db.query("update private.hub_kpi_prepared_facts set amount=81 where fact_id='next-cost' and tenant_id=$1 and generation_id=$2",[t3,g3]);
await assert.rejects(db.query('select private.hub_workify_validate_approved_generation_v1($1,$2)',[t3,g3]),/Existing cost split changed/);
await db.query("update private.hub_kpi_prepared_facts set amount=80 where fact_id='next-cost' and tenant_id=$1 and generation_id=$2",[t3,g3]);
await db.query('select private.hub_workify_validate_approved_generation_v1($1,$2)',[t3,g3]);
const verified=(await db.query("select result from private.hub_workify_activation_runs where tenant_id=$1 and status='verified'",[t3])).rows[0].result;
assert.equal(verified.preparedAmount,125);assert.equal(verified.difference,0);assert.equal(verified.costSplitPreserved,false);
assert.equal(verified.costAmountsAndTargetsPreserved,true);assert.equal(verified.approvedCostGroupChanges,1);
console.log('PASS: approved scope is frozen, publication rejects amount mismatch, uncertain allocation and altered cost split; verified generation preserves cost mappings');
await db.close();
