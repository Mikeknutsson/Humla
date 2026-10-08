const fs=require('node:fs'),ts=require('typescript'),vm=require('node:vm'),assert=require('node:assert/strict');
function load(file){const exports={};const code=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;vm.runInNewContext(code,{exports,require:p=>p==='./payment-forecast'?load('src/lib/hub/payment-forecast.ts'):require(p),Date,Set,Map,Number,Math,Object,Array,Error});return exports}
const {customerTerm,expectedPaymentDate,outcomeForecast}=load('src/lib/hub/payment-outcome-forecast.ts');
const row=(center,kind,date,amount,party='Kund AB',invoiceDate=null,internal=false)=>({center,kind,date,amount,party,invoiceDate,internal});
assert.equal(customerTerm('Linnestofta Maskin AB').days,45);assert.equal(customerTerm('Thomas Håkansson Entreprenad').days,45);assert.equal(customerTerm('Kenny Håkansson').days,30);assert.equal(customerTerm('Elleholms Maskin (STENA)').code,'invoice_30');
assert.equal(expectedPaymentDate(row('30','in','2026-09-01',1,'Linnestofta Maskin AB','2026-09-10')),'2026-10-25');
assert.equal(expectedPaymentDate(row('30','in','2026-09-03',1,'Stena Recycling AB','2026-10-01')),'2026-11-14');
assert.equal(expectedPaymentDate(row('30','in','2026-09-27',1,'Stena Recycling AB')),'2026-11-14');
assert.equal(expectedPaymentDate(row('30','in','2024-02-01',1,'Stena Recycling AB')),'2024-04-14');
assert.equal(expectedPaymentDate(row('30','in','2025-02-01',1,'Stena Recycling AB')),'2025-04-14');
assert.equal(expectedPaymentDate(row('30','in','2026-12-31',1,'Kund AB')),'2027-01-30');
const rows=[];
for(const c of ['20','30','40'])for(const k of ['in','out'])rows.push(row(c,k,'2025-01-01',0),row(c,k,'2025-09-15',100),row(c,k,'2026-09-15',120),row(c,k,'2026-09-30',0),row(c,k,'2025-10-05',1000));
rows.push(row('30','in','2026-10-05',50),row('30','in','2026-09-15',90000,'Elleholms Maskin (STENA)',null,true));
const source={rows,synced_at:'2026-10-08T04:18:06Z',review_rows:0,review_amount:0};let report=outcomeForecast(source,'2026-10-08');
const p=report.weeks[0].parts.find(p=>p.center==='30');assert.equal(p.incoming.factor,1.2);assert.equal(p.incoming.forecast,1150);assert.equal(p.incoming.known,50);assert.equal(report.weeks[0].total.incoming.total,3600);assert.equal(report.internal.history.length,1);
report=outcomeForecast({...source,rows:rows.filter(r=>r.center!=='40')},'2026-10-08');assert.equal(report.weeks[0].total.net,null);assert.equal(report.weeks[0].parts.find(p=>p.center==='40').incoming.forecast,null);
assert.throws(()=>outcomeForecast(source,'2026-10-08',-1),/Leverantörstid/);
console.log('Outcome forecast checks passed: customer terms, Stena month-end/leap/year boundaries, trend, registered remainder, internal exclusions and missing departments.');
if(process.argv[2]){const actual=outcomeForecast(JSON.parse(fs.readFileSync(process.argv[2],'utf8')),'2026-10-08');console.log(JSON.stringify({rows:JSON.parse(fs.readFileSync(process.argv[2],'utf8')).rows.length,trend:actual.automatic.trendFrom+' / '+actual.automatic.trendTo,weeks:actual.weeks.map(w=>({week:w.number,departments:w.parts.map(p=>({kst:p.center,in:p.incoming.total,out:p.outgoing.total,trendIn:p.incoming.factor,trendOut:p.outgoing.factor})),net:w.total.net})),warnings:actual.automatic.warnings},null,2));}
