import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createRequire} from 'node:module';
import ts from 'typescript';
import XLSX from 'xlsx';
const require=createRequire(import.meta.url),m={exports:{}};
new Function('require','module','exports',ts.transpileModule(fs.readFileSync('src/lib/kpi/accounting-reference.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText)(require,m,m.exports);
const {parseAccountingReference}=m.exports;
const rows=[['Kontorubrik','Kontogrupp','Innev års utfall TD','% av oms','Budget','Diff','Föreg års utfall TD'],['Rörelsens intäkter','Total',100,0,0,0,90],['Rörelsens intäkter','Huvudintäkter',100],['Arbetstid','Total',100000],['Personalkostnader','Total',-30],['Avskrivningar','Total',-5],['Bränsle','Total',-10],['Total',null,20,0,0,0,10],['Tillämpade filter:\nMånad (sort enl räkenskapsår) är okt\ndima är 30 Transport eller 20 Sortergården\nRäkenskapsår2_invSort är 26/27\nOH-fördelning aktiv är 0']];
function bytes(r=rows){const b=XLSX.utils.book_new();XLSX.utils.book_append_sheet(b,XLSX.utils.aoa_to_sheet(r),'Export');return XLSX.write(b,{type:'buffer',bookType:'xlsx'});}
const p=parseAccountingReference(bytes());
assert.equal(p.metrics.revenue.value,100);assert.equal(p.metrics.result.value,20);assert.equal(p.metrics.fuel.value,-10);assert.equal(p.metrics.revenue.previous,90);
assert.equal(p.cost_center,'20,30');assert.equal(p.from,'2026-09-01');assert.equal(p.to,'2026-10-31');
assert.throws(()=>parseAccountingReference(bytes(rows.slice(0,-1))),/filter/);
assert.throws(()=>parseAccountingReference(bytes([...rows,['Rörelsens intäkter','Total',200]])),/Entydigt/);
assert.throws(()=>parseAccountingReference(bytes(rows.map(r=>r[0]?.startsWith('Tillämpade')?[r[0].replace('är okt','är okt eller nov')]:r))),/slutmånad/);
if(process.argv[2]){const real=parseAccountingReference(fs.readFileSync(process.argv[2]));console.log(JSON.stringify({from:real.from,to:real.to,cost_center:real.cost_center,revenue:real.metrics.revenue.value,result:real.metrics.result.value}));}
console.log('PASS: exact finance totals, repeated subtotal rejection, cumulative date scope, source filters and previous values.');
