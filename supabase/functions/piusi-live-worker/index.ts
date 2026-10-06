import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"Content-Type":"application/json"}});
Deno.serve(async(req)=>{
 if(req.method!=="POST")return reply({error:"POST required"},405);
 const url=Deno.env.get("SUPABASE_URL")!,key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
 if(!url||!key)return reply({error:"Server configuration missing"},500);
 const db=createClient(url,key,{auth:{persistSession:false}});
 const workerKey=req.headers.get("x-humla-worker-key")||"";
 const {data:authorized,error:authError}=await db.rpc("hub_verify_worker_key",{p_key:workerKey});
 if(authError||!authorized)return reply({error:"Unauthorized"},401);
 const body=await req.json().catch(()=>({}));
 // Hourly cron ticks only perform external calls at 03:00 Stockholm (DST safe).
 if(body.nightly && new Intl.DateTimeFormat("en-GB",{timeZone:"Europe/Stockholm",hour:"2-digit",hourCycle:"h23"}).format(new Date())!=="03")return reply({ok:true,skipped:"Outside nightly window"});
 const from=body.start_date?new Date(body.start_date):new Date(Date.now()-3*86400000);
 const to=body.end_date?new Date(body.end_date):new Date();
 if(!Number.isFinite(from.getTime())||!Number.isFinite(to.getTime())||from>to||to.getTime()-from.getTime()>31*86400000)return reply({error:"Invalid date window (max 31 days)"},400);
 const q=db.from("hub_connections").select("*").eq("connector_type","piusi_bsmart");
 if(body.connection_id)q.eq("id",body.connection_id);
 else q.in("status",["active","error"]);
 const {data:connections,error:connError}=await q;
 if(connError)return reply({error:"Connections unavailable"},500);
 const results=[];
 const readPiusi=async(response:Response,stage:string)=>{
  const text=await response.text();
  if(!response.ok || /^API calls/i.test(text.trim()))throw Error("PIUSI "+stage+" failed (HTTP "+response.status+"): "+(response.status===429||/^API calls/i.test(text.trim())?"API request limit reached; next scheduled run will retry":"upstream request rejected"));
  try{return JSON.parse(text);}catch{throw Error("PIUSI "+stage+" returned a non-JSON response (HTTP "+response.status+")");}
 };
 for(const c of connections||[]){
  try{
   const {data:credentials,error:credError}=await db.rpc("hub_get_connection_credentials",{p_tenant_id:c.tenant_id,p_connection_id:c.id});
   if(credError)throw Error("Credentials unavailable");
   const clientId=credentials?.client_id||Deno.env.get("PIUSI_CLIENT_ID");
   const secret=credentials?.client_secret||Deno.env.get("PIUSI_CLIENT_SECRET");
   if(!clientId||!secret)throw Error("PIUSI credentials missing");
   const base=String(c.configuration?.api_base_url||c.base_url||"https://apibsmartexport.piusi.com").replace(/\/$/,"");
   const ar=await fetch(base+"/api/Auth/token",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({client_id:clientId,client_secret:secret})});
   const token=await readPiusi(ar,"authentication");
   if(!ar.ok||!token.access_token)throw Error("PIUSI authentication failed");
   // Recover missed days with one-day overlap; canonical Hub ingest deduplicates.
   const last=c.last_success_at?new Date(c.last_success_at).getTime():NaN;
   const connectionFrom=body.start_date||!Number.isFinite(last)?from:new Date(Math.max(to.getTime()-31*86400000,Math.min(from.getTime(),last-86400000)));
   const rows=[];
   for(let page=0;page<20;page++){
    const rr=await fetch(base+"/api/v1/Transactions/"+(page*255)+"/255",{method:"POST",headers:{Authorization:"Bearer "+token.access_token,"Content-Type":"application/json"},body:JSON.stringify({start_date:connectionFrom.toISOString(),end_date:to.toISOString()})});
    const payload=await readPiusi(rr,"transactions");
    if(!rr.ok)throw Error("PIUSI transaction fetch failed: "+rr.status);
    const part=Array.isArray(payload)?payload:Array.isArray(payload.items)?payload.items:Array.isArray(payload.data)?payload.data:Array.isArray(payload.results)?payload.results:[];
    rows.push(...part);if(part.length<255)break;
    if(page===19)throw Error("Pagination limit reached; split date window");
   }
   const {data:result,error:syncError}=await db.rpc("hub_sync_piusi_transactions",{p_tenant_id:c.tenant_id,p_connection_id:c.id,p_transactions:rows});
   if(syncError)throw Error(syncError.message);
   if(result?.failed>0)throw Error("Hub could not import "+result.failed+" PIUSI transactions");
   await db.from("hub_connections").update({status:"active",last_success_at:new Date().toISOString(),last_error:null,last_error_at:null}).eq("id",c.id);
   results.push({connection_id:c.id,received:rows.length,result});
  }catch(e){
   const message=e instanceof Error?e.message:"Unknown sync error";
   await db.from("hub_connections").update({status:"error",last_error:message,last_error_at:new Date().toISOString()}).eq("id",c.id);
   results.push({connection_id:c.id,error:message});
  }
 }
 return reply({ok:results.every(x=>!x.error),period:{from:from.toISOString(),to:to.toISOString()},results});
});