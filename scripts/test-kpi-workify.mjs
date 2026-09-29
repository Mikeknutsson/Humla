import './test-kpi-parser.mjs';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {normalizeRows,parseImportFile}=await import('../src/lib/kpi/parser.ts');
const {suggestMapping}=await import('../src/lib/kpi/schema.ts');
const {allocateWorkify,isWorkify}=await import('../src/lib/kpi/workify.ts');
const headers=['Ordernummer','Artikelnummer','Artikeldatum','Summa','Fakturerad','RegNr','Projekt'];
const rows=['P','V','UNKNOWN','V'].map((article,i)=>({Ordernummer:'1',Artikelnummer:article,Artikeldatum:'2026-09-01',Summa:i===3?'bad':'100',Fakturerad:'Ja',RegNr:'ABC123',Projekt:'999'}));
const table={headers,rows};assert.ok(isWorkify(table));
const result=allocateWorkify(normalizeRows(table,'revenue',suggestMapping(headers,'revenue')),[{id:'1',article_number:'P',project_reference:'5100',cost_center:'30',source_hash:'test'},{id:'2',article_number:'V',project_reference:null,cost_center:'30',source_hash:'test'}]);
assert.deepEqual(result.map(r=>r.is_valid),[true,true,false,false]);
assert.equal(result[0].project_reference,'5100');assert.equal(result[0].vehicle_registration,null);assert.equal(result[1].project_reference,null);assert.equal(result[1].vehicle_registration,'ABC123');assert.equal(result[0].source_data.Projekt,'999');assert.equal(result.filter(r=>r.is_valid).reduce((sum,r)=>sum+r.amount,0),200);
const hours=normalizeRows({headers:['Date','Hours'],rows:[{Date:'2026-09-01',Hours:'-5'},{Date:'2026-09-01',Hours:'5'}]},'driver_time',{occurred_on:'Date',paid_hours:'Hours',billable_hours:'Hours',employee_number:'Date'});assert.equal(hours[0].is_valid,false);assert.equal(hours[0].paid_hours,null);assert.equal(hours[1].is_valid,true);
console.log('PASS: exclusive project/vehicle allocation, missing rules quarantined, mixed valid/invalid rows, negative hours preserved for review');
if(process.env.WORKIFY_TEST_FILE){
 const actual=await parseImportFile(new File([await readFile(process.env.WORKIFY_TEST_FILE)],'workify.xlsx'));
 const rules=JSON.parse(await readFile('/tmp/humla-workify-rules.json','utf8')).map((r,i)=>({...r,id:String(i)}));
 const allocated=allocateWorkify(normalizeRows(actual,'revenue',suggestMapping(actual.headers,'revenue')),rules);
 assert.equal(allocated.length,actual.rows.length);
 assert.ok(allocated.every(r=>!r.is_valid||!(r.project_reference&&r.vehicle_registration)));
 console.log(JSON.stringify({total:allocated.length,valid:allocated.filter(r=>r.is_valid).length,review:allocated.filter(r=>!r.is_valid).length,project:allocated.filter(r=>r.is_valid&&r.project_reference).length,vehicle:allocated.filter(r=>r.is_valid&&r.vehicle_registration).length,unmappedArticle:allocated.filter(r=>r.allocation.target==='review').length}));
}
