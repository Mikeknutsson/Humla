import assert from 'node:assert/strict';import{readFile}from'node:fs/promises';
const{PGlite}=await import(process.env.PGLITE_MODULE??'@electric-sql/pglite');const db=new PGlite();
await db.exec(`create schema private;create schema auth;create role anon;create role authenticated;create role service_role;
create function auth.uid()returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
create function public.hub_has_permission(uuid,text)returns boolean language sql as $$select $1='20000000-0000-0000-0000-000000000001'::uuid$$;
create table public.kpi_import_batches(id uuid primary key,tenant_id uuid,status text,file_hash text);
create table public.kpi_import_rows(id uuid,tenant_id uuid,batch_id uuid,data_kind text,occurred_on date,source_data jsonb,project_reference text,paid_hours numeric,is_valid boolean,row_number integer,created_at timestamptz);`);
await db.exec(await readFile(new URL('../supabase/migrations/20261014071510_hub_workshop_time_kpi.sql',import.meta.url),'utf8'));
const t='20000000-0000-0000-0000-000000000001',b='30000000-0000-0000-0000-000000000001',c='30000000-0000-0000-0000-000000000002';
for(const batch of[b,c]){await db.query("insert into public.kpi_import_batches values($1,$2,'completed','hash')",[batch,t]);await db.query("insert into private.hub_workshop_time_sources(tenant_id,batch_id,file_hash,approval_reference)values($1,$2,'hash','test')",[t,batch]);}
const rows=[['A','10',138,'P'],['A','40',9,'OWN'],['A','10',29,'99999'],['B','20',81,'P'],['B','40',55,'OWN'],['B','10',40,'99999']];
let n=0;for(const batch of[b,c])for(const[name,kst,hours,project]of rows){n++;await db.query("insert into public.kpi_import_rows values($1,$2,$3,'next_historical_time','2026-09-10',$4,$5,$6,true,$7,now())",[`80000000-0000-0000-0000-${String(n).padStart(12,'0')}`,t,batch,{Namn:name,'Kostnadsställe nr':kst,Timmar:String(hours),Godkänd:'TRUE',Projektnr:project},project,hours,n]);}
const call=(months=[9])=>db.query("select public.hub_kpi_workshop_time_v1($1,'2026-09-01','2027-08-31',$2)r",[t,months]);
await assert.rejects(call(),/KPI access required/);await db.exec("set test.actor='10000000-0000-0000-0000-000000000001'");
const r=(await call()).rows[0].r;assert.equal(r.work_hours,283);assert.equal(r.billable_hours,219);assert.equal(r.non_billable_hours,64);assert.equal(r.absence_hours,69);assert.equal(r.billing_rate,77.4);assert.equal(r.duplicate_rows,6);
assert.equal(r.people.find(p=>p.name==='A').billing_rate,93.9);assert.equal(r.people.find(p=>p.name==='B').billing_rate,59.6);
assert.equal((await call([10])).rows[0].r.available,false);
await db.query("update public.kpi_import_batches set status='withdrawn'where id=$1",[c]);assert.equal((await call()).rows[0].r.work_hours,283);
await db.query("update public.kpi_import_rows set source_data=source_data||'{\"Kostnadsställe nr\":\"\"}'where source_data->>'Namn'='B'and project_reference='P'");const review=(await call()).rows[0].r;assert.equal(review.review_rows,1);assert.equal(review.billable_hours,138);
assert.equal((await db.query("select has_function_privilege('anon','public.hub_kpi_workshop_time_v1(uuid,date,date,integer[])','execute')a")).rows[0].a,false);
console.log('PASS: 77.4% with absence excluded, staff rates, reimports, withdrawals, month boundaries, unknown centers and anonymous access');await db.close();
