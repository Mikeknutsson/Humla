const fs=require('node:fs'),ts=require('typescript'),vm=require('node:vm'),assert=require('node:assert/strict');
const exportsObject={};let calls=0,queue=[];
const code=ts.transpileModule(fs.readFileSync('src/lib/kpi/import-request.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
vm.runInNewContext(code,{exports:exportsObject,Error,AbortSignal,crypto,fetch:async(_url,options)=>{calls++;assert.equal(options.redirect,'manual');assert.equal(options.credentials,'same-origin');const next=queue.shift();if(next instanceof Error)throw next;return next;}});
const {requestImport,ImportConnectionError}=exportsObject;
const response=(body,status=200)=>Response.json(body,{status});
async function run(items,options){calls=0;queue=items;return requestImport('/api/kpi/parse',new FormData(),options);}
(async()=>{
 assert.deepEqual(await run([new TypeError('Failed to fetch'),response({rows:4})],{readOnly:true}),{rows:4});assert.equal(calls,2);
 await assert.rejects(run([new TypeError('Failed to fetch')],{readOnly:false}),e=>e instanceof ImportConnectionError&&e.reconnect);assert.equal(calls,1);
 await assert.rejects(run([{type:'opaqueredirect',status:0}],{readOnly:true}),e=>e.reconnect&&/Inloggningen/.test(e.message));assert.equal(calls,1);
 await assert.rejects(run([response({error:'Inloggning krävs'},401)],{readOnly:true}),e=>e.reconnect);assert.equal(calls,1);
 await assert.rejects(run([response({error:'Importbehörighet saknas'},403)],{readOnly:true}),/Importbehörighet saknas/);assert.equal(calls,1);
 await assert.rejects(run([new Response('<html>Gateway error</html>',{status:502})],{}),e=>e instanceof ImportConnectionError&&/HTTP 502/.test(e.message));
 await assert.rejects(run([new Response('{broken',{headers:{'Content-Type':'application/json'}})],{}),e=>e instanceof ImportConnectionError&&/Importsvaret avbröts/.test(e.message));
 const timeout=new Error('Timed out');timeout.name='TimeoutError';await assert.rejects(run([timeout],{readOnly:true}),/Svaret dröjde/);assert.equal(calls,1);
 console.log('PASS: safe analysis retry, no save replay, authentication redirects, expired login, permissions, non-JSON errors and timeouts.');
})().catch(e=>{console.error(e);process.exitCode=1});
