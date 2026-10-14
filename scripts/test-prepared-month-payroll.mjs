import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite}=await import(process.env.PGLITE_MODULE??'@electric-sql/pglite');
const db=new PGlite();
await db.exec(`create schema private;
create function private.hub_kpi_active_report_generation_v1(uuid)returns uuid language sql as $$select '60000000-0000-0000-0000-000000000001'::uuid$$;
create function private.hub_kpi_month_scope_v1(integer,integer[])returns integer[] language sql as $$select $2$$;
create table private.hub_kpi_report_generations(id uuid,first_fiscal_year integer,last_fiscal_year integer);
create table private.hub_kpi_prepared_facts(generation_id uuid,tenant_id uuid,fiscal_year integer,fact_id text,occurred_on date,kind text,amount numeric,category text,project text,vehicle text,unit_id uuid,unit_name text,business_group text,source text,description text,account text,file_name text,row_number integer,original jsonb,cost_center text,cost_center_name text,classification_source jsonb);
insert into private.hub_kpi_report_generations values('60000000-0000-0000-0000-000000000001',2025,2026);`);
const migration=await readFile(new URL('../supabase/migrations/20261005200325_kpi_prepared_dataset_read_path.sql',import.meta.url),'utf8');
await db.exec(migration.slice(0,migration.indexOf('CREATE OR REPLACE FUNCTION private.hub_kpi_prepared_daily')));
const tenant='20000000-0000-0000-0000-000000000001';
for(const [id,date,kind,amount,source]of [['sept-order','2026-09-30','revenue',100,'Workify'],['oct-order','2026-10-01','revenue',900,'Workify'],['sept-payroll','2026-09-30','cost',40,'TransPA'],['oct-payroll','2026-10-01','cost',300,'TransPA']]){
 await db.query("insert into private.hub_kpi_prepared_facts(generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,source,cost_center,original)values('60000000-0000-0000-0000-000000000001',$1,2026,$2,$3,$4,$5,$6,'30','{}')",[tenant,id,date,kind,amount,source]);
}
const rows=(await db.query("select fact_id,amount,source from private.hub_kpi_prepared_month_facts_v1($1,2026,array[9],'{\"cost_center\":\"30\"}')order by fact_id",[tenant])).rows;
assert.deepEqual(rows.map(r=>r.fact_id),['sept-order','sept-payroll']);
assert.equal(rows.find(r=>r.source==='TransPA').amount,'40');
assert.equal((await db.query("select count(*) n from private.hub_kpi_prepared_month_facts_v1($1,2026,array[9,10],'{\"cost_center\":\"30\"}')",[tenant])).rows[0].n,4);
console.log('PASS: prepared September financial scope excludes October revenue/payroll and preserves September TransPA cost');
await db.close();
