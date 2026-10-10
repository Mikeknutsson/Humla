import test from 'node:test';
import assert from 'node:assert/strict';
import {buildMarketDiscovery} from '../src/lib/hub/market-discovery.ts';
const asset={make:'Volvo',model:'FH 500',vehicle_type:'Lastbil',source_meter_type:'K_OT_KM',ownership:null};
test('truck searches multiple relevant sources without leaking registration',()=>{
 const p=buildMarketDiscovery({...asset,registration:'ABC123'});
 assert.equal(p.query,'Volvo FH 500');
 assert.deepEqual(p.sources.map(s=>s.name),['Klaravik','Blinto','Retrade','Mascus','Truck1','Autoline']);
 for(const s of p.sources){const u=new URL(s.broad_url);assert.equal(u.hostname,'www.google.com');assert.ok(u.searchParams.get('q').includes('Volvo FH 500'));assert.ok(!s.broad_url.includes('ABC123'));}
});
test('unknown class retains nine sources, missing model does not guess from description',()=>{
 const p=buildMarketDiscovery({...asset,make:null,model:null,vehicle_type:null,description:'Private job ABC123'});
 assert.equal(p.sources.length,9);assert.equal(p.query,'');assert.ok(p.missing.includes('Fordonstyp'));assert.ok(p.missing.includes('Modell'));
});
test('hour-meter machines exclude passenger car sources',()=>{
 const p=buildMarketDiscovery({...asset,vehicle_type:null,source_meter_type:'K_OT_HOURS'});
 assert.ok(p.sources.some(s=>s.name==='Machineryline'));assert.ok(!p.sources.some(s=>s.name==='Kvdbil'));
});
test('year and variant have a separate precise search, broad search retained',()=>{
 const p=buildMarketDiscovery({...asset,ownership:{asset_class:'truck',model_year:2020,variant:'6x2 "lastväxlare"'}});
 const q=new URL(p.sources[0].precise_url).searchParams.get('q');assert.ok(q.includes('2020'));assert.ok(q.includes('6x2'));assert.ok(!q.includes('"'));assert.ok(!new URL(p.sources[0].broad_url).searchParams.get('q').includes('2020'));
});
