import assert from 'node:assert/strict';
import {loadNextToken,nextRowBody,nextDeliveryStatus,assertNextTestConnection} from './next-auth.mjs';
function db(cached=false,storeError=false){
 const refs=['database_number','client_key','client_id','client_secret'].map(n=>({credential_name:n,vault_secret_id:n}));if(cached)refs.push({credential_name:'access_token',vault_secret_id:'access_token'});
 const calls=[];
 return {calls,from(){const q={select(){return q},eq(){return q},maybeSingle(){return Promise.resolve({data:null})},then(fn){return Promise.resolve({data:refs,error:null}).then(fn)}};return q;},async rpc(name,args){calls.push(name);if(name==='hub_internal_vault_secret_v1')return {data:args.p_secret_id==='access_token'?'cached-token':'synthetic-value'};if(name==='hub_next_store_access_token_v1')return storeError?{error:{message:'error'}}:{data:{ok:true}};throw Error('unexpected rpc');}};
}
let network=0;const cached=db(true);assert.equal(await loadNextToken(cached,'tenant','test',async()=>{network++;throw Error('unexpected request')}),'cached-token');assert.equal(network,0);
const bootstrap=db();assert.equal(await loadNextToken(bootstrap,'tenant','test',async()=>{network++;return new Response(JSON.stringify({access_token:'new-token'}),{status:200})}),'new-token');assert.equal(bootstrap.calls.at(-1),'hub_next_store_access_token_v1');
await assert.rejects(loadNextToken(db(),'tenant','test',async()=>new Response('{}',{status:401})),/next_new_one_time_key_required/);
await assert.rejects(loadNextToken(db(false,true),'tenant','test',async()=>new Response('{"access_token":"new-token"}')),/next_token_storage_failed/);
await assert.rejects(loadNextToken(db(),'tenant','test',async()=>{throw Error('sensitive server detail')}),e=>e.message==='next_token_bootstrap_uncertain');
const row={next_workorder_id:123,next_codeno:'ST2',quantity:'1',priceunit:'5956',chargeable:true,showinmobile:true};assert.equal(nextRowBody(row).priceunit,5956);assert.equal(nextRowBody(row).usedquantity,1);
assert.throws(()=>nextRowBody({...row,next_workorder_id:null}),/not_verified/);assert.throws(()=>nextRowBody({...row,quantity:'NaN'}),/invalid/);
assert.equal(nextDeliveryStatus(200,42),'delivered');for(const [status,id,result]of [[200,null,'needs_review'],[500,null,'needs_review'],[422,null,'blocked'],[429,null,'retry']])assert.equal(nextDeliveryStatus(status,id),result);
assert.throws(()=>assertNextTestConnection({connector_type:'next_project_api',configuration:{environment:'production'}}),/next_test_connection_required/);
assert.throws(()=>assertNextTestConnection({connector_type:'next_project_api',configuration:{environment:'test',read_only:true}},true),/next_test_writes_disabled/);
assert.doesNotThrow(()=>assertNextTestConnection({connector_type:'next_project_api',configuration:{environment:'test',read_only:false,outbound_enabled:true,write_mode:'test_only'}},true));
console.log('NEXT adapter checks passed: token reuse/persistence, redacted errors, row validation, uncertain delivery, production/read-only guards.');
