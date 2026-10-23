import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
const context={exports:{}};
vm.runInNewContext(ts.transpileModule(fs.readFileSync('lib/hub/next-cost-reconciliation.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,context);
const {reconcileNextCosts:run}=context.exports;
const base={id:'a',batchId:'batch1',batchStatus:'completed',rowNumber:1,projectReference:'243',occurredOn:'2026-10-13',amount:'200',sourceContentHash:'same',sourceDocumentId:'voucher',sourceDocumentLineId:'1',sourceAccount:'5000'};
assert.equal(run([base])[0].state,'unique_verified');
assert.equal(run([base,{...base,id:'b',batchId:'batch2'}])[1].state,'duplicate_verified');
for(const changed of [{amount:'201'},{sourceContentHash:'different'},{projectReference:'244'}]){
 const r=run([base,{...base,id:'b',batchId:'batch2',...changed}]);
 assert.ok(r.every(x=>x.state==='review_required'));
}
const voucherOnly=[{...base,sourceDocumentLineId:null},{...base,id:'b',batchId:'batch2',sourceDocumentLineId:null}];
assert.ok(run(voucherOnly).every(x=>x.state==='review_required'));
assert.ok(run([base,{...base,id:'b',tenantId:'other'}]).every(x=>x.state==='unique_verified'));
assert.equal(run([{...base,amount:'NaN'}])[0].state,'invalid');
assert.equal(run([{...base,amount:'-200'}])[0].state,'unique_verified');
const r=run([{...base,id:'b',batchId:'batch2'},base]);
assert.equal(r[0].canonicalRowId,'a');assert.equal(r[1].state,'unique_verified');
console.log('PASS: source-line conflicts, voucher-only ambiguity, stable ordering, tenant scope, invalid amounts and credits');
