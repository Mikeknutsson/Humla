import {test} from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
import fs from 'node:fs';
import vm from 'node:vm';
const js=ts.transpileModule(fs.readFileSync('src/lib/hub/car-market-search.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;
const module={exports:{}};
vm.runInNewContext(js,{exports:module.exports,require:()=>({marketSources:[{name:'Kvdbil',kinds:['car']},{name:'Bytbil',kinds:['car']},{name:'Klaravik',kinds:['car']},{name:'Mascus',kinds:['truck']}]}),URL,Set});
const {carSearchPlan,classifyCarCandidates}=module.exports;
test('missing year/variant remain unknown and private identity stays in Hub',()=>{
 const p=carSearchPlan({make:'Volvo',model:'V60 CROSS COUNTRY',registration:'PRIVATE',description:'DRIVER NAME',current_meter:143369,meter_date:'2026-09-16',ownership:null});
 assert.equal(p.meter_km,143369);assert.equal(p.missing.length,2);assert.ok(!p.query.includes('PRIVATE'));assert.ok(!p.query.includes('DRIVER'));assert.ok(!p.query.includes('lastbil'));
});
test('individual listings, auctions and collection pages are separated; KVD aliases deduped',()=>{
 const c=(source,url)=>({source,url,title:'Volvo',snippet:'',date:null});
 const out=classifyCarCandidates([c('Kvdbil','https://www.kvd.se/fast-pris/volvo-123456'),c('Kvdbil','https://www.kvd.se/auktioner/123456'),c('Bytbil','https://www.bytbil.com/skane-lan/personbil-v60-9884-19341942'),c('Bytbil','https://www.bytbil.com/bil/volvo/v60-cross-country'),c('Klaravik','https://www.klaravik.se/auktion/produkt/3289398-volvo/'),c('Mascus','https://www.mascus.se/test')]);
 assert.equal(out.length,4);assert.equal(out[0].page_kind,'listing');assert.equal(out[1].price_kind,'asking');assert.equal(out[2].page_kind,'collection');assert.equal(out[3].price_kind,'auction');
});
