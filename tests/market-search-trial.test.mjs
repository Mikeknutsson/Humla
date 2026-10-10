import {test} from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
import fs from 'node:fs';
import vm from 'node:vm';
const source=fs.readFileSync('src/lib/hub/market-search-trial.ts','utf8');
const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;
const module={exports:{}};
vm.runInNewContext(js,{exports:module.exports,require:()=>({marketSources:[{name:'Klaravik',domain:'klaravik.se'}]}),URL,Set});
const {safeSearchCandidates,trialQuery}=module.exports;
test('untrusted links and duplicates cannot become candidates',()=>{
 const results=['https://www.klaravik.se/item?a=1','https://www.klaravik.se/item?a=2','https://klaravik.se.evil.com/item','javascript:alert(1)','https://user@klaravik.se/item','https://klaravik.se:8443/item','https://blocket.se/item'].map(url=>({url,title:'test',snippet:'not a verified price'}));
 const safe=safeSearchCandidates({results});assert.equal(safe.length,1);assert.equal(safe[0].source,'Klaravik');assert.equal(safe[0].snippet,'not a verified price');
});
test('model code normalization does not transmit registration',()=>assert.equal(trialQuery('SCANIA','R520B8X4*4NB'),'SCANIA R520 8X4 lastbil pris'));
test('provider errors do not generate invented candidates',()=>assert.equal(safeSearchCandidates({error:'timeout'}).length,0));
