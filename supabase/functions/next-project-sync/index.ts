import {loadNextToken,assertNextTestConnection} from "./next-auth.mjs";
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2.57.4";
const TENANT="944597b6-9c46-4bef-998d-f19e23c4245b",CONNECTION="4508d5ad-bd4e-4ca9-9cbf-ff45a0395a34";
const enc=new TextEncoder();
async function sha256(v:unknown){const b=await crypto.subtle.digest("SHA-256",enc.encode(JSON.stringify(v)));return Array.from(new Uint8Array(b)).map(x=>x.toString(16).padStart(2,"0")).join("")}
Deno.serve(async(req)=>{try{
 const sb=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
 const input=await req.json().catch(()=>({}));
 const {data:wref}=await sb.from("hub_secret_references").select("vault_secret_id").eq("credential_name","worker_key").maybeSingle();
 let expected=""; if(wref?.vault_secret_id){const x=await sb.rpc("hub_internal_vault_secret_v1",{p_secret_id:wref.vault_secret_id});expected=String(x.data||"")}
 else {const x=await sb.rpc("hub_get_worker_key_for_internal_use");expected=String(x.data||"")}
 if(!expected||String(input.worker_key||"")!==expected)return new Response('{"ok":false,"error":"unauthorized"}',{status:401,headers:{"content-type":"application/json"}});
 const {data:connection}=await sb.from("hub_connections").select("connector_type,configuration").eq("tenant_id",TENANT).eq("id",CONNECTION).maybeSingle();assertNextTestConnection(connection);const token=await loadNextToken(sb,TENANT,CONNECTION);
 const requested=Array.isArray(input.entities)?input.entities:["projects"]; const endpoints:any={projects:["project/","project"],customers:["customer/","customer"],suppliers:["supplier/","supplier"],users:["user/","user"],workorders:["workorder/","workorder"],supplierInvoices:["supplierinvoice/","supplier_invoice"]}; const allowed=new Set(Object.keys(endpoints)); const run=await sb.from("hub_next_sync_runs").insert({tenant_id:TENANT,connection_id:CONNECTION,status:"running",entity_types:requested}).select("id").single();
 let fetched=0,upserted=0,errors=0; const summary:any={};
 for(const e of requested){if(!allowed.has(e))continue; try{
   const [path,etype]=endpoints[e]; const rr=await fetch("https://api.next-tech.com/v1/"+path+"?page=1&size=50",{headers:{accept:"application/json",Authorization:"Bearer "+token}});
   if(!rr.ok){summary[e]={ok:false,status:rr.status};errors++;continue}
   const jj=await rr.json(); const items=Array.isArray(jj)?jj:(jj?.items??jj?.data??jj?.results??[]);
   for(const v of items){const eid=String(v?.id??v?.projectId??v?.number??v?.projectNumber??"");if(!eid)continue;const wr=await sb.from("hub_next_entities").upsert({tenant_id:TENANT,connection_id:CONNECTION,entity_type:etype,external_id:eid,payload:v,payload_hash:await sha256(v),last_seen_at:new Date().toISOString()},{onConflict:"tenant_id,connection_id,entity_type,external_id"});if(!wr.error)upserted++}
   fetched+=items.length;summary[e]={ok:true,count:items.length};
 }catch(e){errors++;summary[e]={ok:false,error:"sync_failed"}}}
 if(run.data?.id)await sb.from("hub_next_sync_runs").update({status:errors?"partial":"completed",completed_at:new Date().toISOString(),fetched_count:fetched,upserted_count:upserted,error_count:errors,details:summary}).eq("id",run.data.id);
 await sb.from("hub_connections").update({status:errors?"error":"active",last_success_at:errors?null:new Date().toISOString(),last_error_at:errors?new Date().toISOString():null,last_error:errors?"NEXT sync partial/failed":null}).eq("id",CONNECTION);
 return new Response(JSON.stringify({ok:errors===0,auth_ok:true,fetched,upserted,errors,entities:summary}),{headers:{"content-type":"application/json"}});
}catch(e){return new Response(JSON.stringify({ok:false,error:e instanceof Error?e.message:"unknown"}),{status:500,headers:{"content-type":"application/json"}})}});