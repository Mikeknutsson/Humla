import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createRequire} from 'node:module';
import ts from 'typescript';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
const require=createRequire(import.meta.url);
const styles={__esModule:true,default:new Proxy({},{get:(_,key)=>String(key)})};
function compile(path,stubs={}){
 const code=ts.transpileModule(fs.readFileSync(new URL(path,import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX,esModuleInterop:true}}).outputText;
 const m={exports:{}};new Function('require','module','exports',code)(p=>stubs[p]??(p.endsWith('.css')?styles:require(p)),m,m.exports);return m.exports;
}
const periodHelpers=compile('../src/lib/hub/driver-self.ts');
const card=compile('../src/app/chauffor/driver-goal-card.tsx');
const ranges=[{from:'2026-09-30',to:'2026-10-27',mode:'four-weeks',has_economy:true},{from:'2026-10-21',to:'2026-10-27',mode:'week',has_economy:true}];
const calls=[];
const db={auth:{getUser:async()=>({data:{user:{id:'test-user'}}})},from:()=>({select(){return this},eq(){return this},async maybeSingle(){return {data:{tenant_id:'test-tenant',role:'worker'}}}}),rpc:async(name,args)=>{
 calls.push({name,args});
 if(name==='hub_driver_goal_periods_v1')return {data:ranges,error:null};
 return {error:null,data:{status:'ready',name:'Testchaufför',reporting:'good',latest_work_date:'2026-10-27',days:[{date:'2026-10-27',reporting:'good',vehicle:'good'}],vehicle_context:[{name:'Testfordon',coverage_status:'registered',goal_gap_pp:-2,previous_goal_gap_pp:null,year_goal_gap_pp:null,comparison_from:'2026-09-02',comparison_to:'2026-09-29',actions:[]}]}};
}};
const page=compile('../src/app/chauffor/page.tsx',{'next/link':{__esModule:true,default:({children,...props})=>React.createElement('a',props,children)},'next/navigation':{redirect:()=>{throw Error('Unexpected login redirect')}},'@/lib/supabase/server':{createClient:async()=>db},'@/lib/kpi/period':{stockholmToday:()=>({year:2026,month:11,day:4})},'@/lib/hub/driver-self':periodHelpers,'@/app/kpi/login/actions':{logout:async()=>{}},'./driver-goal-card':card});
const html=renderToStaticMarkup(await page.default({searchParams:Promise.resolve({})}));
const report=calls.find(c=>c.name==='hub_driver_self_v1');
assert.equal(report.args.p_from,'2026-09-30');assert.equal(report.args.p_to,'2026-10-27');
assert.match(html,/Testfordon/);assert.match(html,/Under målet/);assert.match(html,/Preliminärt/);assert.match(html,/Tiderna är inskickade/);assert.match(html,/Senaste 4 veckorna/);
assert.doesNotMatch(html,/Inväntar en komplett|Inga tider att visa|bekräftat komplett/);
console.log('PASS: chauffeur page renders vehicle, gauge, reporting and imported periods instead of empty current week');
