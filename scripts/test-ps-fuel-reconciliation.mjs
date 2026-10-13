import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite}=await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const db=new PGlite();
await db.exec(`create schema private;create role anon;create role authenticated;create role service_role;
create table public.kpi_import_rows(id uuid,tenant_id uuid,source_data jsonb);
create table private.hub_kpi_prepared_hub_objects(generation_id uuid,tenant_id uuid,object_type text,data jsonb);
create table private.hub_kpi_prepared_facts(tenant_id uuid,generation_id uuid,fact_id text,occurred_on date,kind text,amount numeric,category text,project text,vehicle text,unit_id uuid,unit_name text,business_group text,source text,account text,cost_center text,original jsonb,display_original jsonb default '{}');
create function private.hub_kpi_prepare_piusi_facts_v1(p_tenant uuid,p_generation uuid)returns void language plpgsql as $$begin
 update private.hub_kpi_prepared_facts f set original=f.original||jsonb_build_object('_humla_fuel_reconciliation',jsonb_build_object('booked_amount',f.amount)),amount=0
 where f.generation_id=p_generation and f.tenant_id=p_tenant and f.source='NEXT' and f.kind='cost' and f.category='fuel' and f.description='PS Olje AB'
 and exists(select 1 from private.hub_kpi_prepared_hub_objects o where o.generation_id=p_generation and o.tenant_id=p_tenant and o.object_type='FuelTransaction' and o.data->>'source_system'='piusi_bsmart'
 and date_trunc('month',(o.data->>'transaction_date')::timestamp)::date=date_trunc('month',f.occurred_on)::date);
end $$;
alter table private.hub_kpi_prepared_facts add column description text;
create function private.hub_kpi_run_report_jobs_v1()returns void language plpgsql as $$declare job record;generation uuid;begin
 perform private.hub_next_validate_revenue_identity_v1(job.tenant_id,generation);end $$;`);
const migration=await readFile(new URL('../supabase/migrations/20261013182005_hub_exact_ps_fuel_reconciliation.sql',import.meta.url),'utf8');
await db.exec(migration.slice(0,migration.indexOf('-- Add verification evidence')));
const tenant='20000000-0000-0000-0000-000000000001',old='60000000-0000-0000-0000-000000000001',next='60000000-0000-0000-0000-000000000002';
for(const[text,account,expected]of [['PS Olje AB','5360',true],['Levfakt PS Olje AB (TEST)','5360',false],['Circle K','5360',false],['PS Olje AB','5631',false],['PS Olje AB ','5360',false],[null,'5360',false]])assert.equal((await db.query('select private.hub_ps_own_tank_source_v1($1,$2)a',[JSON.stringify({'Verifikationstext':text}),account])).rows[0].a,expected);
await db.query(`insert into public.kpi_import_rows values('80000000-0000-0000-0000-000000000001',$1,'{"fixture":true}')`,[tenant]);
const sources=[['ps',100,'2026-09-01','PS Olje AB','5360'],['credit',-10,'2026-09-02','PS Olje AB','5360'],['invoice',40,'2026-09-03','Levfakt PS Olje AB (TEST)','5360'],['circle',50,'2026-09-03','Circle K','5360'],['other-account',60,'2026-09-03','PS Olje AB','5631'],['no-consumption',70,'2026-08-03','PS Olje AB','5360']];
for(const[id,amount,date,text,account]of sources)await db.query(`insert into private.hub_kpi_prepared_facts(tenant_id,generation_id,fact_id,occurred_on,kind,amount,category,project,source,account,cost_center,original)values($1,$2,$3,$4,'cost',$5,'fuel','PROJECT','NEXT',$6,'30',$7)`,[tenant,old,id,date,amount,account,JSON.stringify({'Verifikationstext':text})]);
await db.query(`insert into private.hub_kpi_prepared_facts(tenant_id,generation_id,fact_id,occurred_on,kind,amount,category,source,cost_center,original)values($1,$2,'piusi:accepted','2026-09-04','cost',90,'fuel','Piusi','30','{}')`,[tenant,old]);
await db.query('insert into private.hub_kpi_prepared_facts select (jsonb_populate_record(null::private.hub_kpi_prepared_facts,to_jsonb(f)||jsonb_build_object(\'generation_id\',$2::uuid))).*from private.hub_kpi_prepared_facts f where generation_id=$1',[old,next]);
await db.query('select private.hub_kpi_prepare_piusi_facts_v1($1,$2)',[tenant,next]);
const facts=(await db.query('select fact_id,amount from private.hub_kpi_prepared_facts where generation_id=$1',[next])).rows;
for(const[id,amount]of sources)assert.equal(Number(facts.find(f=>f.fact_id===id).amount),['ps','credit'].includes(id)?0:amount);
const run=(await db.query(`insert into private.hub_ps_fuel_runs(tenant_id,previous_generation,original_hash,expected_rows,expected_amount,approval_reference)select $1,$2,md5(string_agg(md5(to_jsonb(r)::text),','order by id)),2,90,'Synthetic test'from public.kpi_import_rows r where tenant_id=$1 returning id`,[tenant,old])).rows[0].id;
await db.query(`insert into private.hub_ps_fuel_items select $1,tenant_id,fact_id,occurred_on,amount,cost_center,original from private.hub_kpi_prepared_facts where generation_id=$2 and fact_id in('ps','credit')`,[run,old]);
await db.query("update private.hub_kpi_prepared_facts set amount=0 where generation_id=$1 and fact_id='invoice'",[next]);
await assert.rejects(db.query('select private.hub_ps_validate_fuel_v1($1,$2)',[tenant,next]),/unrelated financial rows/);
await db.query("update private.hub_kpi_prepared_facts set amount=40 where generation_id=$1 and fact_id='invoice'",[next]);
await db.query("update private.hub_kpi_prepared_facts set amount=1 where generation_id=$1 and fact_id='ps'",[next]);
await assert.rejects(db.query('select private.hub_ps_validate_fuel_v1($1,$2)',[tenant,next]),/audited originals/);
await db.query("update private.hub_kpi_prepared_facts set amount=0 where generation_id=$1 and fact_id='ps'",[next]);
await db.query('select private.hub_ps_validate_fuel_v1($1,$2)',[tenant,next]);
assert.equal((await db.query('select result from private.hub_ps_fuel_runs')).rows[0].result.difference,0);
assert.equal((await db.query("select has_function_privilege('anon','private.hub_ps_validate_fuel_v1(uuid,uuid)','execute')a")).rows[0].a,false);
console.log('PASS: exact original text despite null description, external invoices/other accounts preserved, credits and absent Piusi months handled, full financial set guarded, original audit retained');
await db.exec(`create function private.hub_kpi_monthly_fuel_sources_v1(p_tenant uuid,integer,integer[],jsonb)returns table(fact_id text,include_cost boolean)language sql as $$
 with piusi_periods as(select 9 m),facts as(select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id='60000000-0000-0000-0000-000000000002'),
 next_fuel as materialized(select f.*,not(coalesce(description,'')='PS Olje AB' and extract(month from occurred_on)::int in(select m from piusi_periods)) include_cost from facts f where source='NEXT' and kind='cost' and category='fuel')
 select fact_id,include_cost from next_fuel;$$;`);
await db.exec(await readFile(new URL('../supabase/migrations/20261013182447_hub_ps_fuel_drilldown_evidence.sql',import.meta.url),'utf8'));
const detail=(await db.query('select * from private.hub_kpi_monthly_fuel_sources_v1($1,2026,array[9],\'{}\')',[tenant])).rows;
for(const[id]of sources)assert.equal(detail.find(f=>f.fact_id===id).include_cost,!['ps','credit'].includes(id));
console.log('PASS: monthly fuel drilldown and KPI use the same applied own-tank reconciliation, preserving all external invoices');
await db.close();
