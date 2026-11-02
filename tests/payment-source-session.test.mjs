import {test} from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
import fs from 'node:fs';
import vm from 'node:vm';

function setup(){
 let now=Date.now();
 class Clock extends Date{static now(){return now;}}
 const js=ts.transpileModule(fs.readFileSync('src/lib/hub/payment-source-session.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
 const module={exports:{}};
 vm.runInNewContext(js,{exports:module.exports,Date:Clock,Map});
 return {...module.exports,advance:ms=>{now+=ms;}};
}
const data=n=>({source:{rows:[{amount:n}]},payroll:{marker:n}});

test('period navigation reuses the same source and payroll; ordinary calculation fetches fresh',async()=>{
 const {paymentSourceSession:load}=setup();let calls=0;
 const fetch=async()=>data(++calls);
 assert.equal((await load('tenant:user:date',false,fetch)).source.rows[0].amount,1);
 assert.equal((await load('tenant:user:date',true,fetch)).reused,true);
 assert.equal(calls,1);
 const fresh=await load('tenant:user:date',false,fetch);
 assert.equal(fresh.source.rows[0].amount,2);assert.equal(fresh.payroll.marker,2);
});

test('tenant, user, report date, expiry and corrections prevent inappropriate reuse',async()=>{
 const {paymentSourceSession:load,invalidatePaymentSourceSessions:invalidate,advance}=setup();let calls=0;
 const fetch=async()=>data(++calls);
 for(const key of ['a:u:1','b:u:1','a:v:1','a:u:2'])assert.equal((await load(key,true,fetch)).reused,false);
 invalidate('a');
 assert.equal((await load('b:u:1',true,fetch)).reused,true);
 assert.equal((await load('a:u:1',true,fetch)).reused,false);
 advance(300001);
 assert.equal((await load('b:u:1',true,fetch)).reused,false);
});

test('failed refresh does not leave an old snapshot available as a successful refresh',async()=>{
 const {paymentSourceSession:load}=setup();
 await load('a:u:1',false,async()=>data(1));
 await assert.rejects(load('a:u:1',false,async()=>{throw Error('source unavailable');}));
 const fresh=await load('a:u:1',true,async()=>data(2));
 assert.equal(fresh.reused,false);assert.equal(fresh.source.rows[0].amount,2);
});
