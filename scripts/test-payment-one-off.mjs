import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
// Run with Node 24: node --experimental-strip-types scripts/test-payment-one-off.mjs
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'humla-payment-test-'));
try{
 for(const name of ['payment-forecast','payment-payroll-forecast','payment-outcome-forecast']){
  const source=fs.readFileSync(`src/lib/hub/${name}.ts`,'utf8').replace(/from '(\.\/payment-[^']+)'/g,"from '$1.ts'");
  fs.writeFileSync(path.join(temp,name+'.ts'),source);
 }
 const {outcomeForecast}=await import(pathToFileURL(path.join(temp,'payment-outcome-forecast.ts')));
 const row=(id,date,amount,oneOff=false)=>({id,rowId:id,center:'20',kind:'out',date,amount,party:id,invoiceDate:null,internal:false,oneOff});
 const rows=[row('coverage','2025-01-01',0),row('prior-trend','2025-09-15',100),row('trend','2026-09-15',150),row('coverage-end','2026-10-27',0),row('recurring','2025-11-19',1000),row('crushing','2025-11-21',2000),row('registered','2026-10-27',100,true)];
 const run=rows=>outcomeForecast({rows,synced_at:'2026-10-27',review_rows:0,review_amount:0},'2026-10-27');
 const get=r=>r.automatic.breakdown.find(d=>d.weekFrom==='2026-12-14'&&d.center==='20'&&d.kind==='out'&&!d.internal);
 const original=run(rows);assert.equal(get(original).total,4500);
 const marked=run(rows.map(r=>r.id==='crushing'?{...r,oneOff:true}:r));assert.equal(get(marked).baseline,1000);assert.equal(get(marked).total,1500);assert.equal(get(marked).excludedBaseline,2000);
 assert.equal(original.weeks[0].parts.find(p=>p.center==='20').outgoing.known,100,'known one-off payments remain');
 const changedTrend=run([...rows.map(r=>r.id==='trend'?{...r,amount:100}:r),row('one-off-trend','2026-09-15',50,true)]);assert.equal(get(changedTrend).trendCurrent,100);assert.equal(get(changedTrend).factor,1);
 assert.equal(get(run(rows)).total,4500,'undo restores the forecast');
 for(const r of [original,marked,changedTrend])for(const d of r.automatic.breakdown){
  const p=r.weeks.find(w=>w.from===d.weekFrom).parts.find(p=>p.center===d.center);
  if(!d.internal)assert.equal(d.total,p[d.kind==='in'?'incoming':'outgoing'].total);
  for(const key of ['baselineRows','knownRows','trendPreviousRows','trendCurrentRows'])for(const id of d[key])assert.ok(r.automatic.auditRows.some(row=>row.id===id),'audit row must resolve');
 }
 assert.equal(new Set(marked.automatic.auditRows.map(r=>r.id)).size,marked.automatic.auditRows.length,'shared audit rows are serialized once');
 console.log('PASS: one-off baseline/trend, known payments, undo, breakdown reconciliation and audit references');
}finally{fs.rmSync(temp,{recursive:true,force:true});}
