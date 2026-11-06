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
const comparison=shared.monthlyComparisonSections({month:{metrics:[],accounting_basis:{personnel_comparison:{calculated_cost:1000,transpa_estimate:700,next_personnel_cost:200,provisional_work_cost:100,other_personnel_cost:0,booked_cost:1200,cost_difference:-200,result_effect:200,overhead_allocation:300,management_allocation:100,next_management_cost:50,basis:'Personal och overhead jämförs separat.'}}},ytd:{metrics:[],accounting_basis:{personnel_comparison:{calculated_cost:3000,booked_cost:2900,cost_difference:100,result_effect:-100}}},previous:{month:{metrics:[],accounting_basis:{personnel_comparison:{calculated_cost:0,booked_cost:0,cost_difference:0,result_effect:0}}},ytd:{metrics:[]}}}).find(s=>s.key==='personnel');
assert.deepEqual(comparison.rows.find(r=>r.label==='Resultateffekt av skillnaden i personalkostnad').values,[200,-100,0,undefined]);
assert.deepEqual(comparison.rows.find(r=>r.label==='Personalkostnad i Humlas modell').values,[1000,3000,0,undefined]);
assert.equal(comparison.rows.find(r=>r.label==='Separat: fördelad overhead').values[0],300);
assert.equal(comparison.note,'Personal och overhead jämförs separat.');
const exports=load('src/lib/kpi/monthly-report-export.ts',name=>name==='./monthly-report'?shared:require(name));
const report=process.argv[2]?JSON.parse(fs.readFileSync(process.argv[2],'utf8')):{tenant:'Test',title:'Nyckeltal Transport',period:{from:'2026-01-01',to:'2026-01-31',ytd_from:'2025-09-01'},scope:{cost_center:'20,30'},generation:'test',synced_at:'2026-02-01T02:20:00Z',invoicing_rule:'Alla registrerade intäkter räknas som fakturerade.',month:{metrics:[{key:'revenue',label:'Fakturerad omsättning',value:100,unit:'kr',status:'source',basis:'Rapportregel'},{key:'billing',label:'Debiterbar tid',value:null,unit:'%',status:'missing',basis:'Underlag saknas'}],vehicles:[],recorded_revenue:100,uninvoiced_revenue:0,fuel:null,fuel_share:null,estimated_payroll:null,active_vehicle_count:0},ytd:{metrics:[{key:'revenue',value:500,status:'partial'},{key:'billing',value:null,status:'missing'}],vehicles:[],recorded_revenue:500,uninvoiced_revenue:0,fuel:null,fuel_share:null,estimated_payroll:null,active_vehicle_count:0},indicators:{reported_vehicle_utilization:null,definition:'Inte debiterbar tid'}};
const workbook=XLSX.read(exports.monthlyExcel(report),{type:'buffer'});
assert.equal(workbook.SheetNames.length,17);
assert.ok(workbook.SheetNames.includes('Stena perioder'));
assert.ok(workbook.SheetNames.includes('Kontrolltal bokföring'));
assert.ok(workbook.SheetNames.includes('Bokföringsavstämning'));
const rows=XLSX.utils.sheet_to_json(workbook.Sheets.Nyckeltal);
assert.equal(rows[0].Månad,report.month.metrics[0].value);
assert.equal(rows[0].YTD,report.ytd.metrics[0].value);
for(const [i,m] of report.month.metrics.entries())if(m.value===null){assert.equal(rows[i].Månad,undefined);assert.equal(rows[i].Status,'Underlag saknas');}
assert.equal(shared.monthlyValue(null,'%'),'Underlag saknas');
assert.ok(shared.monthlyValue(0,'kr').startsWith('0'));
const pdf=await PDFDocument.load(await exports.monthlyPdf(report));assert.ok(pdf.getPageCount()>0);
console.log('Monthly Excel/PDF: values, YTD, missing data, numeric cells and readable PDF verified.');
