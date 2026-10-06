import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import ts from 'typescript';
import * as XLSX from 'xlsx';
import {PDFDocument} from 'pdf-lib';
const require=createRequire(import.meta.url);
function moduleCode(path){return ts.transpileModule(fs.readFileSync(path,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;}
function load(path,customRequire=require){const module={exports:{}};new Function('require','module','exports',moduleCode(path))(customRequire,module,module.exports);return module.exports;}
const shared=load('src/lib/kpi/monthly-report.ts');
const exports=load('src/lib/kpi/monthly-report-export.ts',name=>name==='./monthly-report'?shared:require(name));
const report=process.argv[2]?JSON.parse(fs.readFileSync(process.argv[2],'utf8')):{tenant:'Test',title:'Nyckeltal Transport',period:{from:'2026-01-01',to:'2026-01-31',ytd_from:'2025-09-01'},scope:{cost_center:'20,30'},generation:'test',synced_at:'2026-02-01T02:20:00Z',invoicing_rule:'Alla registrerade intäkter räknas som fakturerade.',month:{metrics:[{key:'revenue',label:'Fakturerad omsättning',value:100,unit:'kr',status:'source',basis:'Rapportregel'},{key:'billing',label:'Debiterbar tid',value:null,unit:'%',status:'missing',basis:'Underlag saknas'}],vehicles:[],recorded_revenue:100,uninvoiced_revenue:0,fuel:null,fuel_share:null,estimated_payroll:null,active_vehicle_count:0},ytd:{metrics:[{key:'revenue',value:500,status:'partial'},{key:'billing',value:null,status:'missing'}],vehicles:[],recorded_revenue:500,uninvoiced_revenue:0,fuel:null,fuel_share:null,estimated_payroll:null,active_vehicle_count:0},indicators:{reported_vehicle_utilization:null,definition:'Inte debiterbar tid'}};
const workbook=XLSX.read(exports.monthlyExcel(report),{type:'buffer'});
assert.equal(workbook.SheetNames.length,5);
const rows=XLSX.utils.sheet_to_json(workbook.Sheets.Nyckeltal);
assert.equal(rows[0].Månad,report.month.metrics[0].value);
assert.equal(rows[0].YTD,report.ytd.metrics[0].value);
for(const [i,m] of report.month.metrics.entries())if(m.value===null){assert.equal(rows[i].Månad,undefined);assert.equal(rows[i].Status,'Underlag saknas');}
assert.equal(shared.monthlyValue(null,'%'),'Underlag saknas');
assert.ok(shared.monthlyValue(0,'kr').startsWith('0'));
const pdf=await PDFDocument.load(await exports.monthlyPdf(report));assert.ok(pdf.getPageCount()>0);
console.log('Monthly Excel/PDF: values, YTD, missing data, numeric cells and readable PDF verified.');
