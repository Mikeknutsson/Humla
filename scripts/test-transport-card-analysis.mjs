import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {analyzeTransportCard,buildTransportCardAnalyses} from '../src/lib/hub/transport-card-analysis.ts';

const metrics={revenue:100000,cost:95000,result:5000,margin_percent:5,target_margin_percent:10,deviation_amount:-5000,deviation_pp:-5,missing_targets:0,rows:10};
const input=(id,overrides={})=>({unit_id:id,unit_name:id,business_group:'Kranbilar',revenue:100000,personnel:25000,service_repair:5000,fuel:10000,worked_hours:100,...overrides});
const high=input('self',{service_repair:25000,worked_hours:200});
const peers=[input('other1'),input('other2')];
const before=JSON.stringify(high);
const a=analyzeTransportCard(metrics,high,input('self'),[high,...peers]);
assert.equal(a.status,'warning');
assert.equal(a.insights.length,2);
assert.ok(a.insights.some(x=>x.title.includes('arbetstid')));
assert.ok(a.insights.some(x=>x.title.includes('reparationskostnad')));
assert.ok(a.insights.every(x=>x.evidence.some(e=>e.includes('föregående år'))&&x.evidence.some(e=>e.includes('2 andra'))));
assert.equal(JSON.stringify(high),before,'analysis must not mutate financial input');
const missing=analyzeTransportCard({...metrics,target_margin_percent:null,deviation_pp:null,deviation_amount:null},input('self',{worked_hours:null}),null,[]);
assert.equal(missing.status,'unknown');
assert.ok(!missing.insights.some(x=>x.title.includes('arbetstid')));
assert.ok(missing.limitations.some(x=>x.includes('TransPA')));
assert.equal(analyzeTransportCard(metrics,input('self',{revenue:0}),null,peers).insights.length,0);
assert.equal(analyzeTransportCard({...metrics,deviation_pp:1},high,null,peers).insights.length,0);
assert.equal(analyzeTransportCard(metrics,high,null,[peers[0]]).insights.length,0,'one peer does not establish a benchmark');
assert.equal(analyzeTransportCard(metrics,input('self',{service_repair:4999}),input('self',{service_repair:0}),[]).insights.length,0,'small cost is not material');
const report={units:[{...metrics,unit_id:'self',unit_name:'self'}],groups:[],analysis_inputs:[high,...peers,input('noise',{business_group:'Stena',service_repair:999999}),input('self',{business_group:'Ej klassificerat',revenue:0,personnel:0,service_repair:1000,fuel:0,worked_hours:null})]};
const analysis=buildTransportCardAnalyses(report,null);
assert.ok(analysis.units.self.insights.some(x=>x.title.includes('arbetstid')),'zero-revenue overhead classification must not discard valid time');
assert.ok(analysis.units.self.insights.every(x=>x.evidence.every(e=>!e.includes('Stena'))),'other areas must not become peers');
if(process.argv.includes('--live')) {
 const current=JSON.parse(readFileSync('/tmp/transport-live-report.json','utf8'));
 const old=JSON.parse(readFileSync('/tmp/transport-prior-report.json','utf8'));
 const live=buildTransportCardAnalyses(current,old);
 assert.equal(Object.keys(live.units).length,current.units.length);
 assert.equal(Object.keys(live.groups).length,current.groups.length);
 console.log(JSON.stringify({liveExamples:Object.entries(live.units).filter(([,x])=>x.insights.length).slice(0,3).map(([id,analysis])=>({unit:current.units.find(u=>u.unit_id===id)?.unit_name,analysis})),groups:Object.entries(live.groups).filter(([,a])=>a.insights.length).length},null,2));
}
assert.equal(analyzeTransportCard(metrics,input('self',{service_repair:12000}),input('self',{service_repair:9000}),[]).insights.length,0,'moderate deviations stay quiet');
console.log('PASS: goal status, history, peer exclusion, minimum evidence, missing hours, mixed cost classifications and immutable inputs');
