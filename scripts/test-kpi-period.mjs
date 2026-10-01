import assert from 'node:assert/strict';
import fs from 'node:fs';
import ts from 'typescript';
import vm from 'node:vm';
const code=ts.transpileModule(fs.readFileSync('src/lib/kpi/period.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;
const context={exports:{},Intl,Date,Number,URLSearchParams,Error};vm.runInNewContext(code,context);
const {parseMonthPeriod,monthPeriodQuery,monthPeriodFromDates}=context.exports;
const period=parseMonthPeriod(undefined,undefined,new Date('2026-08-31T22:30:00Z'));
assert.equal(period.fiscalYear,2026);
assert.deepEqual(Array.from(period.months),[9,10,11,12,1,2,3,4,5,6,7,8]);
const selected=parseMonthPeriod('2025','1,9,10,9');
assert.deepEqual(Array.from(selected.months),[9,10,1]);
assert.equal(new URLSearchParams(monthPeriodQuery(selected)).get('months'),'9,10,1');
for(const invalid of ['','0','13','x'])assert.throws(()=>parseMonthPeriod('2025',invalid));
console.log('KPI fiscal-period regression tests passed.');

assert.equal(monthPeriodFromDates('2025-09-01','2026-08-31').fiscalYear,2025);
assert.deepEqual(Array.from(monthPeriodFromDates('2025-09-01','2026-01-31').months),[9,10,11,12,1]);
for(const [from,to] of [['2025-09-02','2026-01-31'],['2025-09-01','2026-09-30'],['2025-02-31','2025-03-31']])assert.equal(monthPeriodFromDates(from,to),undefined);
