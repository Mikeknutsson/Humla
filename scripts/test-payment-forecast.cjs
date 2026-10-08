const fs=require('node:fs'),ts=require('typescript'),vm=require('node:vm'),assert=require('node:assert/strict');
function load(path){const code=ts.transpileModule(fs.readFileSync(path,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;const exports={};vm.runInNewContext(code,{exports,require,Date,Set,Map,Number,Math,Object,Array,Error});return exports}
const {paymentForecast}=load('src/lib/hub/payment-forecast.ts');
const {parsePaymentCsv}=load('src/lib/hub/payment-import.ts');
const row=(id,center,kind,date,amount,internal=false)=>({id,center,kind,date,amount,internal});
const base={asOf:'2026-01-01',ledger:[],history:[],historyFrom:'',historyTo:''};
let r=paymentForecast(base);assert.equal(r.weeks[0].number,5);assert.equal(r.weeks[0].from,'2026-01-26');assert.equal(r.weeks[3].number,8);assert.equal(r.weeks[0].total.net,null);
const history=[];
for(const c of ['20','30'])for(const k of ['in','out']){
 history.push(row(`${c}${k}old`,c,k,'2024-10-01',100),row(`${c}${k}new`,c,k,'2025-10-01',120),row(`${c}${k}target`,c,k,'2025-01-27',1000));
}
const data={...base,history,historyFrom:'2024-09-01',historyTo:'2025-12-31',ledger:[row('known','30','in','2026-01-26',300),row('internal','30','in','2026-01-26',500,true),row('unknown','','out','2026-01-27',50)]};
r=paymentForecast(data);const p=r.weeks[0].parts.find(p=>p.center==='30');assert.equal(p.incoming.factor,1.2);assert.equal(p.incoming.forecast,900);assert.equal(p.incoming.total,1200);assert.equal(r.weeks[0].total.incoming.total,2400);assert.equal(r.unknown.length,1);assert.equal(r.excludedInternal,1);
const withInternal=paymentForecast({...data,history:[...data.history,row('int-prior','30','in','2024-10-01',90000,true),row('int-current','30','in','2025-10-01',100000,true),row('int-baseline','30','in','2025-01-27',50000,true)]});
assert.equal(withInternal.weeks[0].parts.find(p=>p.center==='30').incoming.forecast,900);assert.equal(withInternal.weeks[0].total.incoming.total,2400);assert.equal(withInternal.internal.history.length,3);assert.equal(withInternal.internal.ledger[0].amount,500);assert.equal(withInternal.excludedInternal,4);
r=paymentForecast({...data,ledger:[row('above','30','in','2026-01-26',1500)]});assert.equal(r.weeks[0].parts.find(p=>p.center==='30').incoming.forecast,0);
assert.throws(()=>paymentForecast({...base,ledger:[row('a','20','in','2026-02-30',1)]}),/datum/i);
assert.throws(()=>paymentForecast({...base,ledger:[row('a','20','in','2026-02-01',1),row('a','20','in','2026-02-01',1)]}),/Dubblett/);
assert.throws(()=>paymentForecast({...data,historyTo:'2026-01-01'}),/avslutad/);
assert.throws(()=>paymentForecast({...base,inDays:NaN}),/betalningstid/);
r=paymentForecast({...data,basis:'booked',inDays:7,outDays:7});assert.equal(r.weeks[1].parts.find(p=>p.center==='30').incoming.total,1200);
const parsed=parsePaymentCsv('\uFEFFid;kst;typ;datum;belopp;intern\r\n"a;b";30;in;2026-01-26;123,45;nej\r\n');assert.equal(parsed[0].id,'a;b');assert.equal(parsed[0].amount,123.45);
assert.throws(()=>parsePaymentCsv('id;kst;typ;datum;belopp;intern\n1;30;in;2026-01-26;;nej'),/belopp/);
assert.throws(()=>parsePaymentCsv('id;kst;typ;datum;belopp;intern\n"unclosed'),/Oavslutat/);
console.log('Payment forecast checks passed (week/year boundary, trend, totals, lag, missing data, duplicates, CSV).');

const next=paymentForecast({...data,periodOffset:4});assert.equal(next.weeks[0].number,9);assert.equal(next.weeks[3].number,12);const back=paymentForecast({...data,periodOffset:-4});assert.equal(back.weeks[0].number,1);assert.equal(back.weeks[3].number,4);assert.throws(()=>paymentForecast({...data,periodOffset:1.5}),/prognosperiod/);const excluded=paymentForecast({...data,ledger:[...data.ledger,row('workshop','40','in','2026-01-26',999999)]});assert.equal(excluded.weeks[0].total.incoming.total,2400);assert.equal(excluded.weeks[0].parts.length,2);

assert.equal(withInternal.weeks[0].parts.find(p=>p.center==='30').internal.incoming,55555.56);assert.equal(withInternal.weeks[0].internal.incoming,null);assert.equal(withInternal.weeks[0].total.incoming.total,2400);
