import {test} from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
import fs from 'node:fs';
import vm from 'node:vm';
const module={exports:{}};
vm.runInNewContext(ts.transpileModule(fs.readFileSync('src/lib/kpi/foreman-period.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,{exports:module.exports,URLSearchParams,Date,Set});
const {resolveForemanPeriod:resolve,foremanPeriodQuery:query,foremanMonthsContiguous:continuous}=module.exports;
const today={year:2026,month:11,day:2};

test('October and November share an exact month selection and survive URL roundtrip',()=>{
 const p=resolve({fiscal_year:'2026',period_mode:'months',months:'11,10'},null,today);
 assert.equal(p.from,'2026-10-01');assert.equal(p.to,'2026-11-30');assert.equal(p.months.join(','),'10,11');assert.equal(continuous(p),true);
 const url=new URLSearchParams(query(p,'selected-user'));
 assert.equal(url.get('user_id'),'selected-user');assert.equal(url.get('months'),'10,11');
 const restored=resolve(Object.fromEntries(url),null,today);
 assert.equal(restored.from,p.from);assert.equal(restored.to,p.to);assert.equal(restored.months.join(','),p.months.join(','));
});

test('separate months span the fiscal year but never include intervening months',()=>{
 const p=resolve({fiscal_year:'2026',period_mode:'months',months:'1,10'},null,today);
 assert.equal(p.from,'2026-10-01');assert.equal(p.to,'2027-01-31');assert.equal(p.months.join(','),'10,1');assert.equal(continuous(p),false);
 assert.equal(p.months.includes(11),false);assert.equal(p.months.includes(12),false);
 const adjacent=resolve({fiscal_year:'2026',period_mode:'months',months:'1,12'},null,today);
 assert.equal(continuous(adjacent),true);
});

test('YTD, year, leap day and legacy single-month bookmarks keep their behavior',()=>{
 const ytd=resolve({},null,today);assert.equal(ytd.from,'2026-09-01');assert.equal(ytd.to,'2026-11-02');
 assert.equal(resolve({period_mode:'year'},null,today).to,'2027-08-31');
 assert.equal(resolve({period_mode:'month',fiscal_year:'2027',month:'2'},null,today).to,'2028-02-29');
 for(const months of ['', '0','13','10,10','10,invalid'])assert.throws(()=>resolve({period_mode:'months',months},null,today));
});
