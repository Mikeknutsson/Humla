import {test} from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
import fs from 'node:fs';
import vm from 'node:vm';
const module={exports:{}};
vm.runInNewContext(ts.transpileModule(fs.readFileSync('src/lib/hub/payment-weekly-transfer.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,{exports:module.exports});
const {weeklyTransfers,weeklyTransferText}=module.exports;
const week=(number,year,incoming,outgoing)=>({number,year,from:'2026-12-28',to:'2027-01-03',total:{incoming:{total:incoming},outgoing:{total:outgoing},net:incoming===null||outgoing===null?null:incoming-outgoing}});

test('weekly transfer preserves ISO week year, zero, negative net and exact approved totals',()=>{
 const rows=weeklyTransfers({weeks:[week(53,2026,1234.56,2000),week(1,2027,0,0)]});
 const lines=weeklyTransferText(rows,'\t').split('\r\n');
 assert.equal(lines.length,3);
 assert.deepEqual(lines[1].split('\t'),['2026-V53','2026-12-28','2027-01-03','1234,56','2000,00','-765,44']);
 assert.ok(lines[2].endsWith('0,00\t0,00\t0,00'));
 const incoming=rows.reduce((s,r)=>s+r.incoming,0),outgoing=rows.reduce((s,r)=>s+r.outgoing,0);
 assert.equal(incoming-outgoing,rows.reduce((s,r)=>s+r.net,0));
 assert.ok(weeklyTransferText(rows,';').includes('"1234,56";"2000,00";"-765,44"'));
});

test('missing weekly totals stay missing and cannot be exported as zero',()=>{
 const rows=weeklyTransfers({weeks:[week(45,2026,null,50)]});
 assert.equal(rows[0].incoming,null);assert.equal(rows[0].net,null);assert.equal(rows[0].complete,false);
 assert.throws(()=>weeklyTransferText(rows,';'),/Komplett veckoprognos saknas/);
 assert.throws(()=>weeklyTransferText([],'\t'),/Komplett veckoprognos saknas/);
});
