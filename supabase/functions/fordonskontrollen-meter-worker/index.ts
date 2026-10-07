import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"Content-Type":"application/json","Cache-Control":"no-store"}});
const entities={odometer_readings:{path:"/odometers",type:"odometer_km"},engine_hour_readings:{path:"/engine_hours",type:"engine_hours"}};
const dateParameter=(iso:string)=>new Date(iso).toISOString().replace('T',' ').slice(0,19);

Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return reply({error:"POST required"},405);
 const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!key)return reply({error:"Server configuration missing"},500);
 const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:authorized,error:authError}=await db.rpc("hub_verify_worker_key",{p_key:req.headers.get("x-humla-worker-key")??""});
 if(authError||!authorized)return reply({error:"Unauthorized"},401);
 const body=await req.json().catch(()=>({}));
 if(!/^[a-f0-9-]{36}$/i.test(body.connection_id??""))return reply({error:"Connection required"},400);
 const connectionId=body.connection_id;let job:any;
 const state=async(action:string,payload:object={})=>{
  const {data,error}=await db.rpc("hub_fleet_meter_job_v1",{p_connection_id:connectionId,p_action:action,p_payload:{lease_id:job?.lease_id,...payload}});
  if(error)throw Error(error.message);return data;
 };
 try{
  job=await state("claim");if(job.skipped)return reply({ok:true,...job});
  const {data:connection,error:connectionError}=await db.from("hub_connections").select("id,tenant_id,base_url,configuration").eq("id",connectionId).single();
  if(connectionError||!connection||connection.tenant_id!==job.tenant_id)throw Error("Connection unavailable");
  const {data:credentials,error:credentialError}=await db.rpc("hub_get_connection_credentials",{p_tenant_id:job.tenant_id,p_connection_id:connectionId});
  if(credentialError)throw Error("Connection credentials unavailable");
  const token=credentials?.api_token??Deno.env.get("FORDONSKONTROLL_API_TOKEN"),secret=credentials?.api_secret??Deno.env.get("FORDONSKONTROLL_API_SECRET");
  if(!token)throw Error("Fordonskontrollen credentials missing");
  const base=String(connection.configuration?.api_base_url||connection.base_url||"https://fordonskontroll.app/external/api/fleet_manager/v1").replace(/\/$/,"");
  // Do not send configured credentials to an arbitrary URL.
  if(new URL(base).origin!=="https://fordonskontroll.app")throw Error("Unexpected Fordonskontrollen API origin");
  const headers:Record<string,string>={Accept:"application/json",Authorization:`Bearer ${token}`};if(secret)headers["X-TOKEN-SECRET"]=secret;
  const started=Date.now();let pages=0;
  for(const [entity,spec] of Object.entries(entities)){
   while(!job.cursors[entity].done && pages<6 && Date.now()-started<85000){
    const cursor=job.cursors[entity].cursor;
    const query=new URLSearchParams({limit:"100",datetime_from:dateParameter(job.since_at)});if(cursor)query.set("cursor",cursor);
    const response=await fetch(base+spec.path+"?"+query,{headers,signal:AbortSignal.timeout(25000)});
    if(!response.ok)throw Error(`${entity}: upstream HTTP ${response.status}`);
    const data=await response.json();
    const rows=Array.isArray(data)?data:Array.isArray(data.data)?data.data:Array.isArray(data.items)?data.items:Array.isArray(data.results)?data.results:null;
    if(!rows)throw Error(`${entity}: unexpected API response`);
    const next=typeof data.next_cursor==="string"&&data.next_cursor?data.next_cursor:null;
    if(next&&next===cursor)throw Error(`${entity}: repeated pagination cursor`);
    for(let offset=0;offset<rows.length;offset+=50){
     const {data:result,error}=await db.rpc("hub_sync_fordonskontroll_meter_readings",{p_tenant_id:job.tenant_id,p_connection_id:connectionId,p_reading_type:spec.type,p_readings:rows.slice(offset,offset+50)});
     if(error)throw Error(`${entity}: ${error.message}`);
     if(result?.failed>0)throw Error(`${entity}: ${result.failed} readings failed validation (${String(result.errors?.[0]?.error??'unknown validation error').slice(0,500)})`);
     // RPC persists unmapped evidence in Hub review; only retained rows may advance.
     if(Number(result?.skipped??0)>Number(result?.sent_to_review??0))throw Error(`${entity}: unmapped readings were not retained for review`);
    }
    job=await state("progress",{entity,cursor_state:{cursor:next,done:!next},received:rows.length});pages++;
   }
  }
  const done=Object.values(job.cursors).every((value:any)=>value.done);
  job=await state(done?"complete":"release");
  return reply({ok:true,status:job.status,run_id:job.run_id,received:job.received,pages});
 }catch(error){
  const message=error instanceof Error?error.message:"Meter sync failed";
  if(job?.lease_id)await state("fail",{error:message}).catch(()=>{});
  return reply({ok:false,error:message},502);
 }
});
