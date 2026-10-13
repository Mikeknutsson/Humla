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
await db.exec(`create function private.hub_kpi_run_report_jobs_v1() returns void language plpgsql as $$declare job record;generation uuid;begin perform private.hub_workify_validate_approved_generation_v1(job.tenant_id,generation);end $$;`);
await db.exec(await readFile(new URL('../supabase/migrations/20261013164903_hub_next_verified_overlap_scope.sql',import.meta.url),'utf8'));
const nextTenant='20000000-0000-0000-0000-000000000004';
const nextA='70000000-0000-0000-0000-000000000004',nextB='70000000-0000-0000-0000-000000000005';
await db.query("insert into public.kpi_import_batches(id,tenant_id,data_kind,status)values($1,$3,'cost','completed'),($2,$3,'cost','completed')",[nextA,nextB,nextTenant]);
const nextSource={Konto:'5656',Projektnr:'9001','Verifikation nr':'TEST-1',Leverantör:'Test supplier',Nettobelopp:'100.00'};
for(const [batch,ordinal,amount,source] of [[nextA,1,100,nextSource],[nextA,2,100,nextSource],[nextB,1,100,nextSource],[nextB,2,100,{...nextSource,'Upparb intäkt':'0.00'}],[nextB,3,-100,{...nextSource,Nettobelopp:'-100.00'}],[nextB,4,100,{...nextSource,Leverantör:'Other supplier'}]]){
 await db.query("insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,amount,currency,is_valid,source_data,account,project_reference)values($1,$2,$3,'cost','2026-09-01',$4,'SEK',true,$5,'5656','9001')",[nextTenant,batch,ordinal,amount,JSON.stringify(source)]);
}
const nextHash=(await db.query('select md5(string_agg(to_jsonb(r)::text,\'\'order by id))hash from public.kpi_import_rows r where tenant_id=$1',[nextTenant])).rows[0].hash;
assert.equal((await db.query('select private.hub_next_record_reexports_v1($1,$2)n',[nextTenant,'Isolated test approval'])).rows[0].n,2);
assert.equal((await db.query('select private.hub_next_record_reexports_v1($1,$2)n',[nextTenant,'Idempotent rerun'])).rows[0].n,0);
const includedNext=(await db.query("select count(*)n,sum(amount)amount from public.kpi_import_rows r where tenant_id=$1 and private.hub_kpi_import_row_in_scope_v2(id,data_kind,occurred_on,amount,is_valid,validation_errors,source_data)",[nextTenant])).rows[0];
assert.equal(includedNext.n,4);assert.equal(Number(includedNext.amount),200);
assert.equal((await db.query('select md5(string_agg(to_jsonb(r)::text,\'\'order by id))hash from public.kpi_import_rows r where tenant_id=$1',[nextTenant])).rows[0].hash,nextHash);
console.log('PASS: NEXT re-export guard preserves genuine identical occurrences, credits and distinct suppliers; repeats are excluded once without modifying originals');
const nextOld='60000000-0000-0000-0000-000000000004',nextNew='60000000-0000-0000-0000-000000000005';
await db.query("insert into private.hub_kpi_prepared_facts(tenant_id,generation_id,fact_id,occurred_on,kind,amount,source,original) select tenant_id,$2,id::text,occurred_on,'cost',amount,'NEXT',source_data from public.kpi_import_rows where tenant_id=$1",[nextTenant,nextOld]);
await db.query("insert into private.hub_kpi_prepared_facts(tenant_id,generation_id,fact_id,occurred_on,kind,amount,source,original) select tenant_id,$2,id::text,occurred_on,'cost',amount,'NEXT',source_data from public.kpi_import_rows r where tenant_id=$1 and not exists(select 1 from private.hub_next_reexport_audit a where a.row_id=r.id)",[nextTenant,nextNew]);
await db.query("insert into private.hub_next_reexport_activation(tenant_id,previous_generation,original_hash,expected_rows,expected_removed,approval_reference) select $1,$2,md5(string_agg(md5(to_jsonb(r)::text),','order by id)),2,200,'Isolated test' from public.kpi_import_rows r where tenant_id=$1",[nextTenant,nextOld]);
await db.query("update private.hub_kpi_prepared_facts set amount=101 where tenant_id=$1 and generation_id=$2 and amount=100",[nextTenant,nextNew]);
await assert.rejects(db.query('select private.hub_next_validate_reexport_generation_v1($1,$2)',[nextTenant,nextNew]),/changed other financial rows/);
await db.query("update private.hub_kpi_prepared_facts set amount=100 where tenant_id=$1 and generation_id=$2 and amount=101",[nextTenant,nextNew]);
await db.query('select private.hub_next_validate_reexport_generation_v1($1,$2)',[nextTenant,nextNew]);
const nextVerified=(await db.query('select result from private.hub_next_reexport_activation where tenant_id=$1',[nextTenant])).rows[0].result;
assert.equal(nextVerified.removedRows,2);assert.equal(nextVerified.difference,0);assert.equal(nextVerified.otherFactsPreserved,true);
console.log('PASS: NEXT publication rejects unrelated amount changes and verifies exactly the approved removals');
const nextC='70000000-0000-0000-0000-000000000006';
await db.query("insert into public.kpi_import_batches(id,tenant_id,data_kind,status)values($1,$2,'cost','pending')",[nextC,nextTenant]);
for(let ordinal=1;ordinal<=3;ordinal++) await db.query("insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,amount,currency,is_valid,source_data,account,project_reference)values($1,$2,$3,'cost','2026-09-01',100,'SEK',true,$4,'5656','9001')",[nextTenant,nextC,ordinal,JSON.stringify(nextSource)]);
await db.exec("select set_config('test.actor','',false)");
await assert.rejects(db.query("update public.kpi_import_batches set status='completed' where id=$1",[nextC]),/KPI management required/);
await db.exec("select set_config('test.actor','10000000-0000-0000-0000-000000000001',false);create or replace function public.hub_has_permission(uuid,text) returns boolean language sql as $$select true$$;");
await db.query("update public.kpi_import_batches set status='completed' where id=$1",[nextC]);
assert.equal((await db.query('select count(*)n from private.hub_next_reexport_audit where tenant_id=$1',[nextTenant])).rows[0].n,4);
assert.equal((await db.query("select count(*)n from public.kpi_import_rows r where tenant_id=$1 and private.hub_kpi_import_row_in_scope_v2(id,data_kind,occurred_on,amount,is_valid,validation_errors,source_data)",[nextTenant])).rows[0].n,5);
console.log('PASS: authenticated completed-file hook rejects unauthorized changes, excludes repeated exports and preserves an additional genuine occurrence');
await db.exec(`create table public.kpi_cost_category_rules(tenant_id uuid,account text,cost_category text,valid_from date,valid_to date);
create function private.hub_kpi_financial_facts_v1(uuid,date,date) returns void language plpgsql as $$declare x record;cr record;f record;begin
 perform x.source_data||jsonb_build_object('_humla_include_in_vehicle_result',cr.include_in_vehicle_result);
 perform 1 where f.k='cost' and f.src='NEXT' and f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','');end $$;
create function private.hub_kpi_financial_month_facts_v1(uuid,date,date,integer[]) returns void language plpgsql as $$declare x record;cr record;f record;begin
 perform x.source_data||jsonb_build_object('_humla_include_in_vehicle_result',cr.include_in_vehicle_result);
 perform 1 where f.k='cost' and f.src='NEXT' and f.raw#>>'{_humla_assignment,shared_cost}' not in ('none','');end $$;`);
await db.exec(await readFile(new URL('../supabase/migrations/20261013171324_hub_next_missing_financial_cost_scope.sql',import.meta.url),'utf8'));
const completeTenant='20000000-0000-0000-0000-000000000005',completeA='70000000-0000-0000-0000-000000000007',completeB='70000000-0000-0000-0000-000000000008';
await db.query("insert into public.kpi_import_batches(id,tenant_id,data_kind,status)values($1,$3,'cost','needs_review'),($2,$3,'cost','needs_review')",[completeA,completeB,completeTenant]);
await db.query("insert into public.kpi_cost_category_rules values($1,'5656','service_repair','2025-09-01',null),($1,'4015','personnel','2025-09-01',null)",[completeTenant]);
const completeSource={...nextSource,'Verifikation nr':'16D1','Inkludera i rapporter':'TRUE'};
const completeRows=[
 [completeA,1,100,'5656',completeSource], [completeA,2,100,'5656',completeSource],
 [completeB,1,100,'5656',completeSource], [completeB,2,100,'5656',{...completeSource,'Upparb intäkt':'0'}],
 [completeA,3,-30,'5656',{...completeSource,Nettobelopp:'-30.00'}],
 [completeA,4,500,'1181',{...completeSource,Konto:'1181',Nettobelopp:'500.00'}],
 [completeA,5,70,'5656',{...completeSource,'Inkludera i rapporter':'FALSE',Nettobelopp:'70.00'}],
 [completeA,6,80,'4015',{...completeSource,Konto:'4015',Nettobelopp:'80.00'}],
 [completeA,7,90,'5656',{...completeSource,Leverantör:'Elleholms test',Nettobelopp:'90.00'}],
 [completeA,8,0,'5656',{...completeSource,Nettobelopp:'0'}],
];
for(const [batch,ordinal,amount,account,source] of completeRows) await db.query("insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,amount,account,project_reference,currency,is_valid,validation_errors,source_data)values($1,$2,$3,'cost','2026-09-01',$4,$5,'9001','SEK',false,'[\"Kostnadsfördelning behöver granskas\"]',$6)",[completeTenant,batch,ordinal,amount,account,JSON.stringify(source)]);
const completeStates=(await db.query('select review_state,count(*)n,sum(amount)amount from private.hub_next_completeness_rows_v1($1)group by 1',[completeTenant])).rows;
assert.equal(completeStates.find(r=>r.review_state==='candidate_include_unallocated').n,3);
assert.equal(Number(completeStates.find(r=>r.review_state==='candidate_include_unallocated').amount),170);
assert.equal(completeStates.find(r=>r.review_state==='reexport').n,2);
assert.equal(completeStates.find(r=>r.review_state==='account_rule_review').n,1);
assert.equal(completeStates.find(r=>r.review_state==='source_policy_review').n,3);
const completeOld='60000000-0000-0000-0000-000000000006',completeNew='60000000-0000-0000-0000-000000000007';
const completeRun=(await db.query("insert into private.hub_next_completeness_runs(tenant_id,previous_generation,expected_rows,expected_amount,original_hash,approval_reference)select $1,$2,3,170,md5(string_agg(md5(to_jsonb(r)::text),','order by id)),'Isolated test' from public.kpi_import_rows r where tenant_id=$1 returning id",[completeTenant,completeOld])).rows[0].id;
await db.query("insert into private.hub_next_completeness_items(row_id,run_id,tenant_id,amount,occurred_on,account,evidence)select row_id,$2,$1,amount,occurred_on,account,'{}'from private.hub_next_completeness_rows_v1($1)where review_state='candidate_include_unallocated'",[completeTenant,completeRun]);
await db.query("insert into private.hub_kpi_prepared_facts(tenant_id,generation_id,fact_id,kind,amount,original)values($1,$2,'unchanged-revenue','revenue',200,'{}'),($1,$3,'unchanged-revenue','revenue',200,'{}')",[completeTenant,completeOld,completeNew]);
await db.query("insert into private.hub_kpi_prepared_facts(tenant_id,generation_id,fact_id,occurred_on,kind,amount,source,original)select r.tenant_id,$2,r.id::text,r.occurred_on,'cost',r.amount,'NEXT',private.hub_next_completion_source_v1(r.id,r.source_data)from public.kpi_import_rows r join private.hub_next_completeness_items i on i.row_id=r.id where r.tenant_id=$1",[completeTenant,completeNew]);
await db.query("update private.hub_kpi_prepared_facts set vehicle='GUESSED'where tenant_id=$1 and generation_id=$2 and kind='cost'",[completeTenant,completeNew]);
await assert.rejects(db.query('select private.hub_next_validate_completeness_v1($1,$2)',[completeTenant,completeNew]),/Uncertain NEXT allocation/);
await db.query("update private.hub_kpi_prepared_facts set vehicle=null where tenant_id=$1 and generation_id=$2 and kind='cost'",[completeTenant,completeNew]);
await db.query("update private.hub_kpi_prepared_facts set amount=201 where tenant_id=$1 and generation_id=$2 and kind='revenue'",[completeTenant,completeNew]);
await assert.rejects(db.query('select private.hub_next_validate_completeness_v1($1,$2)',[completeTenant,completeNew]),/changed other financial rows/);
await db.query("update private.hub_kpi_prepared_facts set amount=200 where tenant_id=$1 and generation_id=$2 and kind='revenue'",[completeTenant,completeNew]);
await db.query('select private.hub_next_validate_completeness_v1($1,$2)',[completeTenant,completeNew]);
assert.equal((await db.query('select result from private.hub_next_completeness_runs where id=$1',[completeRun])).rows[0].result.difference,0);
console.log('PASS: NEXT completeness preserves multiplicity and credits, holds source-policy and unmapped-account rows, rejects guessed vehicles and unrelated financial changes');
await db.exec(await readFile(new URL('../supabase/migrations/20261013171815_hub_next_completeness_review_api.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../supabase/migrations/20261013172201_hub_next_completion_withdrawal_guard.sql',import.meta.url),'utf8'));
const completionReview=(await db.query('select public.hub_next_completeness_review_v1($1,0,$2)r',[completeTenant,'included_unallocated'])).rows[0].r;
assert.equal(completionReview.selectedRows,3);assert.equal(completionReview.activation.active,true);
assert.equal((await db.query("select has_function_privilege('anon','public.hub_next_completeness_review_v1(uuid,integer,text)','execute')a")).rows[0].a,false);
await assert.rejects(db.query('select public.hub_next_completeness_review_v1($1,0,$2)',[completeTenant,'invented']),/Invalid NEXT review selection/);
const approvedCost=(await db.query('select * from public.kpi_import_rows where id in(select row_id from private.hub_next_completeness_items where tenant_id=$1)limit 1',[completeTenant])).rows[0];
assert.equal((await db.query('select private.hub_next_approved_cost_in_scope_v1($1,$2,$3,$4)a',[approvedCost.id,approvedCost.occurred_on,approvedCost.amount,'[]'])).rows[0].a,true);
assert.equal((await db.query('select private.hub_next_approved_cost_in_scope_v1($1,$2,$3,$4)a',[approvedCost.id,approvedCost.occurred_on,Number(approvedCost.amount)+1,'[]'])).rows[0].a,false);
await db.query("update public.kpi_import_batches set status='failed',provenance='{"+'"withdrawal":{}'+"}'where id=$1",[completeA]);
assert.equal((await db.query('select private.hub_next_approved_cost_in_scope_v1($1,$2,$3,$4)a',[approvedCost.id,approvedCost.occurred_on,approvedCost.amount,'[]'])).rows[0].a,false);
assert.equal((await db.query('select public.hub_next_completeness_review_v1($1,0,$2)r',[completeTenant,'included_unallocated'])).rows[0].r.selectedRows,0);
console.log('PASS: completion review protects access, exposes active vs pending status, and honors later withdrawals and changed economic values');
await db.exec(await readFile(new URL('../supabase/migrations/20261013183930_hub_next_financial_flag_is_not_validity.sql',import.meta.url),'utf8'));
await db.query("update public.kpi_import_batches set provenance='{}',status='needs_review'where id=$1",[completeA]);
const flagIndependent=(await db.query('select review_state,count(*)n,sum(amount)amount from private.hub_next_completeness_rows_v1($1)group by 1',[completeTenant])).rows;
assert.equal(flagIndependent.find(r=>r.review_state==='candidate_include_unallocated').n,4);
assert.equal(Number(flagIndependent.find(r=>r.review_state==='candidate_include_unallocated').amount),240);
assert.equal(flagIndependent.find(r=>r.review_state==='source_policy_review').n,2);
await db.query(`insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,amount,account,project_reference,currency,is_valid,validation_errors,source_data)
 values($1,$2,20,'cost','2026-09-01',15,'5656','9001','SEK',false,'["Kostnadsfördelning behöver granskas"]',$3)`,[completeTenant,completeA,JSON.stringify({...completeSource,Leverantör:'','Verifikation nr':'16D20',Verifikationstext:'Levfakt External supplier (12345)',Nettobelopp:'15.00','Inkludera i rapporter':'FALSE'})]);
const invoiceId=(await db.query('select id from public.kpi_import_rows where tenant_id=$1 and row_number=20',[completeTenant])).rows[0].id;
assert.equal((await db.query('select review_state from private.hub_next_completeness_rows_v1($1)where row_id=$2',[completeTenant,invoiceId])).rows[0].review_state,'candidate_include_unallocated');
console.log('PASS: TRUE/FALSE never substitutes for validity; external voucher evidence qualifies without supplier-field guesses, while internal/unmapped rows remain held');
await db.close();
