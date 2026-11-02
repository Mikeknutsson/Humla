const fs=require('node:fs'),ts=require('typescript'),vm=require('node:vm'),assert=require('node:assert/strict');
function load(file){const exports={};const code=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;vm.runInNewContext(code,{exports,require:p=>p.startsWith('./payment-')?load('src/lib/hub/'+p.slice(2)+'.ts'):require(p),Date,Set,Map,Number,Math,Object,Array,Error});return exports}
const {customerTerm,expectedPaymentDate,outcomeForecast}=load('src/lib/hub/payment-outcome-forecast.ts');
const row=(center,kind,date,amount,party='Kund AB',invoiceDate=null,internal=false)=>({center,kind,date,amount,party,invoiceDate,internal});
assert.equal(customerTerm('Linnestofta Maskin AB').days,45);assert.equal(customerTerm('Thomas Håkansson Entreprenad').days,45);assert.equal(customerTerm('Kenny Håkansson').days,30);assert.equal(customerTerm('Elleholms Maskin (STENA)').code,'stena_month_end');
assert.equal(expectedPaymentDate(row('30','in','2026-09-01',1,'Linnestofta Maskin AB','2026-09-10')),'2026-10-25');
assert.equal(expectedPaymentDate(row('30','in','2026-09-03',1,'Stena Recycling AB','2026-10-01')),'2026-11-14');
assert.equal(expectedPaymentDate(row('30','in','2026-09-27',1,'Stena Recycling AB')),'2026-11-14');
assert.equal(expectedPaymentDate(row('30','in','2026-09-27',1,'Elleholms Maskin (STENA)','2026-10-01')),'2026-11-14');
assert.equal(customerTerm('  ELLEHOLMS MASKIN (stena) ').code,'stena_month_end');
assert.equal(expectedPaymentDate(row('30','in','2024-02-01',1,'Stena Recycling AB')),'2024-04-14');
assert.equal(expectedPaymentDate(row('30','in','2025-02-01',1,'Stena Recycling AB')),'2025-04-14');
assert.equal(expectedPaymentDate(row('30','in','2026-12-31',1,'Kund AB')),'2027-01-30');

require('./test-payment-evidence-model.cjs');
