import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2.57.4";
import {loadNextToken,nextRowBody,nextDeliveryStatus,assertNextTestConnection} from "./next-auth.mjs";
const TENANT="944597b6-9c46-4bef-998d-f19e23c4245b",CONNECTION="4508d5ad-bd4e-4ca9-9cbf-ff45a0395a34";
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json"}});
Deno.serve(async(req)=>{try{
 if(req.method!=="POST")return reply({ok:false,error:"method_not_allowed"},405);
 const sb=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
 const input=await req.json().catch(()=>({}));
 const {data:wref}=await sb.from("hub_secret_references").select("vault_secret_id").eq("credential_name","worker_key").maybeSingle();
 const w=wref?.vault_secret_id?await sb.rpc("hub_internal_vault_secret_v1",{p_secret_id:wref.vault_secret_id}):{data:null};
 if(!w.data||String(input.worker_key||"")!==w.data)return reply({ok:false,error:"unauthorized"},401);
 const dry=input.commit!==true;
 const {data:connection,error:ce}=await sb.from("hub_connections").select("connector_type,configuration").eq("tenant_id",TENANT).eq("id",CONNECTION).maybeSingle();
 if(ce)throw new Error("next_connection_unavailable");
 assertNextTestConnection(connection,!dry);
 const limit=Number.isInteger(input.limit)?Math.max(1,Math.min(input.limit,50)):20;
 const {data:rows,error}=await sb.from("hub_next_outbound_rows").select("*").eq("tenant_id",TENANT).in("status",["pending","retry"]).order("created_at").limit(limit);
 if(error)throw new Error("next_queue_unavailable");
 const results:any[]=[];
 let token:string|null=null;
 for(const row of rows||[]){
  let body;
  try {
   body=nextRowBody(row);
   const [{data:link,error:le},{data:mapping,error:me}]=await Promise.all([
    sb.from("hub_next_workorder_links").select("next_workorder_id").eq("tenant_id",TENANT).eq("source_system",row.source_system).eq("source_order_id",row.source_order_id).maybeSingle(),
    sb.from("hub_next_article_mappings").select("next_codeno,mapping_status").eq("tenant_id",TENANT).eq("source_system",row.source_system).eq("source_article_code",row.payload?.source_article_code||row.payload?.Artikelnummer||"").maybeSingle()
   ]);
   if(le||me)throw new Error("next_mapping_lookup_failed");
   if(link?.next_workorder_id!==row.next_workorder_id)throw new Error("next_workorder_link_not_verified");
   if(mapping?.mapping_status!=="confirmed"||mapping.next_codeno!==row.next_codeno)throw new Error("next_article_mapping_not_confirmed");
  }catch(e){results.push({id:row.id,status:"blocked",error:e instanceof Error?e.message:"next_validation_failed"});continue;}
  if(dry){results.push({id:row.id,status:"validated",body});continue;}
  token??=await loadNextToken(sb,TENANT,CONNECTION);
  const attempt=new Date().toISOString();
  // Compare-and-set ensures two workers cannot POST the same source row.
  const claim=await sb.from("hub_next_outbound_rows").update({status:"sending",last_attempt_at:attempt,attempt_count:row.attempt_count+1}).eq("tenant_id",TENANT).eq("id",row.id).eq("status",row.status).is("next_workorderrow_id",null).select("id").maybeSingle();
  if(claim.error)throw new Error("next_claim_failed");
  if(!claim.data){results.push({id:row.id,status:"already_claimed"});continue;}
  let httpStatus:number|null=null,nid:number|null=null,status="needs_review",validationErrors:unknown=null;
  try {
   const response=await fetch("https://api.next-tech.com/v1/workorderrow/",{method:"POST",headers:{Authorization:"Bearer "+token,"content-type":"application/json",accept:"application/json"},body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
   httpStatus=response.status;
   const result=await response.json().catch(()=>null);
   if(response.status===422&&Array.isArray(result?.detail))validationErrors=result.detail.map((x:any)=>({loc:x.loc,type:x.type}));
   nid=Number.isSafeInteger(result?.id)&&result.id>0?result.id:null;
   status=nextDeliveryStatus(response.status,nid);
  }catch{/* The remote POST may have succeeded. Never resend automatically. */}
  const receipt=await sb.from("hub_next_delivery_receipts").insert({tenant_id:TENANT,outbound_row_id:row.id,operation:"POST /workorderrow/",http_status:httpStatus,next_object_id:nid,response_meta:{status,attempt_at:attempt,validation_errors:validationErrors}});
  if(receipt.error)throw new Error("next_receipt_storage_failed_requires_review");
  const update=await sb.from("hub_next_outbound_rows").update({status,next_workorderrow_id:status==="delivered"?nid:null,delivered_at:status==="delivered"?new Date().toISOString():null,last_error:status==="delivered"?null:status==="needs_review"?"Delivery uncertain; reconcile with NEXT before retry":"NEXT HTTP "+httpStatus}).eq("tenant_id",TENANT).eq("id",row.id).eq("status","sending").eq("last_attempt_at",attempt);
  if(update.error)throw new Error("next_delivery_state_failed_requires_review");
  results.push({id:row.id,status,http_status:httpStatus,next_workorderrow_id:nid});
 }
 return reply({ok:results.every(x=>["validated","delivered","already_claimed"].includes(x.status)),dry_run:dry,count:results.length,results});
}catch(e){return reply({ok:false,error:e instanceof Error?e.message:"next_failed"},502);}});
