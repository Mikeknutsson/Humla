const fs=require('node:fs'),ts=require('typescript'),vm=require('node:vm'),assert=require('node:assert/strict');
function load(file){const exports={};const code=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;vm.runInNewContext(code,{exports,require:p=>p.startsWith('./payment-')?load('src/lib/hub/'+p.slice(2)+'.ts'):require(p),Date,Set,Map,Number,Math,Object,Array,Error});return exports;}
const {outcomeForecast,expectedPaymentDate,customerTerm}=load('src/lib/hub/payment-outcome-forecast.ts');
const day=86400000,rows=[];
for(let n=Date.parse('2024-01-01');n<=Date.parse('2026-11-02');n+=day){const date=new Date(n).toISOString().slice(0,10);for(const [center,kind,amount]of[['30','in',100],['30','out',50],['20','in',30],['20','out',10],['40','out',5]])rows.push({center,kind,date,amount,party:kind==='in'?'Kund AB':'Leverantör AB',invoiceDate:null,internal:false});}
const stena=(date,amount,amountStatus)=>({center:'30',kind:'in',date,amount,party:'Stena Recycling AB',invoiceDate:null,internal:false,amountStatus});
rows.push(stena('2025-09-01',0,'settled'),stena('2025-10-15',1000,'settled'),stena('2025-11-15',1100,'settled'),stena('2026-10-15',500,'settled'),stena('2026-10-20',300,'history'),stena('2026-11-01',0,'history'));
const source={rows,synced_at:'2026-11-02T07:00:00Z',review_rows:0,review_amount:0};
const report=outcomeForecast(source,'2026-11-02');const s=report.automatic.stenaMonths[0];
assert.equal(s.deliveryMonth,'2026-10-01');assert.equal(s.paymentDate,'2026-12-15');assert.equal(s.registered,800);assert.equal(s.remaining,200);assert.equal(s.total,1000);
assert.equal(report.weeks.find(w=>w.number===51).parts.find(p=>p.center==='30').incoming.total,1700);
assert.equal(report.automatic.transfer.incoming,4640);assert.equal(report.automatic.transfer.outgoing,1820);assert.equal(report.automatic.transfer.net,2820);
assert.equal(report.automatic.transfer.registeredIncoming,1190);assert.equal(report.automatic.transfer.registeredOutgoing,195);
assert.equal(report.automatic.transfer.net,report.weeks.reduce((s,w)=>s+w.total.net,0));
const october=outcomeForecast(source,'2026-10-30');for(const w of october.weeks){const same=report.weeks.find(x=>x.from===w.from);if(same){assert.equal(w.total.outgoing.total,same.total.outgoing.total);assert.equal(w.total.incoming.total,same.total.incoming.total);}}
const closed=outcomeForecast({...source,periodReviews:[{scope:'stena',center:'30',kind:'in',month:'2026-10-01',reviewed:true}]},'2026-11-02');assert.equal(closed.automatic.stenaMonths[0].total,800);assert.equal(closed.automatic.stenaMonths[0].remaining,0);
const spikeOrdinary=outcomeForecast({...source,rows:rows.map(r=>!r.amountStatus&&r.kind==='in'&&r.date.startsWith('2026')?{...r,amount:r.amount*100}:r)},'2026-11-02');assert.equal(spikeOrdinary.automatic.stenaMonths[0].total,1000);
const reviews=[];for(const y of[2025,2026])for(const m of['07','08','09'])reviews.push({scope:'ordinary',center:'30',kind:'out',month:`${y}-${m}-01`,reviewed:true});
const growthRows=rows.map(r=>r.center==='30'&&r.kind==='out'&&/^2026-(07|08|09)/.test(r.date)?{...r,amount:r.amount*1.2}:r);
const growth=outcomeForecast({...source,rows:growthRows,periodReviews:reviews},'2026-11-02');const d=growth.automatic.breakdown.find(x=>x.center==='30'&&x.kind==='out'&&!x.internal);assert.equal(d.factor,1.2);assert.equal(d.reviewedTrendMonths.length,3);assert.equal(d.trendStatus,'reviewed');
const partial=outcomeForecast({...source,rows:growthRows,periodReviews:reviews.slice(1)},'2026-11-02');assert.equal(partial.automatic.breakdown.find(x=>x.center==='30'&&x.kind==='out'&&!x.internal).factor,1);
const missing=outcomeForecast({...source,rows:rows.filter(r=>r.center!=='20')},'2026-11-02');assert.equal(missing.automatic.transfer.net,null);assert.ok(missing.automatic.transfer.missing.some(x=>x.center==='20'));
const inactiveStena=outcomeForecast({...source,rows:[...rows,{...stena('2024-04-01',500,'settled'),center:'20'}]},'2026-11-02');assert.equal(inactiveStena.automatic.transfer.net,2820);assert.equal(inactiveStena.automatic.stenaMonths.some(s=>s.center==='20'),false);
const irrelevant=outcomeForecast({...source,rows:[...rows,{center:'90',kind:'out',date:'2026-10-31',amount:999999,party:'X',invoiceDate:null,internal:false}]},'2026-11-02');assert.equal(irrelevant.automatic.transfer.net,2820);
const knownOneOff={center:'30',kind:'out',date:'2026-10-31',amount:23000,party:'One-off',invoiceDate:null,internal:false,oneOff:true,rowId:'test'};
const marked=outcomeForecast({...source,rows:[...rows,knownOneOff]},'2026-11-02');assert.equal(marked.weeks[0].parts.find(p=>p.center==='30').outgoing.known,23150);
const credit=outcomeForecast({...source,rows:[...rows,{...knownOneOff,oneOff:false,amount:-100}]},'2026-11-02');assert.equal(credit.automatic.transfer.registeredOutgoing,95);assert.ok(credit.automatic.auditRows.some(r=>r.amount===-100));
const internal=outcomeForecast({...source,rows:[...rows,{...knownOneOff,amount:900000,internal:true}]},'2026-11-02');assert.equal(internal.automatic.transfer.net,2820);
assert.equal(customerTerm('Elleholms Maskin (STENA)').code,'stena_month_end');assert.equal(expectedPaymentDate(stena('2024-02-01',1,'settled')),'2024-04-14');
assert.throws(()=>outcomeForecast(source,'2026-11-02',-1),/Leverantörstid/);
console.log('PASS: period transfer reconciliation, no calendar-month jump, monthly Stena/date/provenance, closed month has no top-up, source isolation, reviewed trend threshold, missing scope, one-offs and internal exclusions.');
const {periodFingerprints,validatePeriodReviews}=load('src/lib/hub/payment-period-review.ts');
const hash=periodFingerprints(source.rows),reviewRecord={scope:'stena',center:'30',kind:'in',month:'2026-10-01',reviewed:true,sourceHash:hash('stena','30','in','2026-10-01')};
assert.equal(validatePeriodReviews([...source.rows].reverse(),[reviewRecord])[0].stale,false);
const correctedRows=source.rows.map(r=>r.amountStatus==='history'&&r.date==='2026-10-20'?{...r,amount:250}:r);
assert.equal(validatePeriodReviews(correctedRows,[reviewRecord])[0].stale,true);
const staleClosed=outcomeForecast({...source,periodReviews:validatePeriodReviews(correctedRows,[reviewRecord])},'2026-11-02');assert.equal(staleClosed.automatic.stenaMonths[0].reviewed,false);assert.equal(staleClosed.automatic.stenaMonths[0].remaining,200);
const unrelatedRows=[...source.rows,{center:'20',kind:'out',date:'2026-09-01',amount:99,party:'X',invoiceDate:null,internal:false}];assert.equal(validatePeriodReviews(unrelatedRows,[reviewRecord])[0].stale,false);
console.log('PASS: source fingerprints survive row order, invalidate changed source months and preserve unrelated reviews.');

module.exports={report,source,missing};
