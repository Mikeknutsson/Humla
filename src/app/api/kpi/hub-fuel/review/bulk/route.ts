import {createClient} from "@/lib/supabase/server";
export async function POST(req:Request){
 const s=await createClient();const {data:{user}}=await s.auth.getUser();if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data:m}=await s.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").maybeSingle();if(!m)return Response.json({error:"Ingen aktiv organisation"},{status:403});
 const {data:ok}=await s.rpc("hub_has_permission",{p_tenant_id:m.tenant_id,p_permission:"kpi.manage"});if(!ok)return Response.json({error:"Administratörsbehörighet krävs"},{status:403});
 const body=await req.json().catch(()=>null);const items=body?.items;
 if(!Array.isArray(items)||!items.length||items.length>100||!["approved","rejected"].includes(body.status)||typeof body.note!=="string"||body.note.trim().length<3||items.some((x:any)=>typeof x.id!=="string"||!(/^[a-f0-9-]{36}$/i.test(x.id))||(body.status==="approved"&&(!(typeof x.correctedCost==="number")||!Number.isFinite(x.correctedCost)||x.correctedCost<=0))))return Response.json({error:"Ogiltigt urval, pris eller motivering (max 100 rader)"},{status:400});
 const ids=items.map((x:any)=>x.id);if(new Set(ids).size!==ids.length)return Response.json({error:"Urvalet innehåller dubbletter"},{status:400});
 const {data:sources,error:sourceError}=await s.from("kpi_bsmart_fuel_reviewed_v2").select("hub_object_id,cost_status").eq("tenant_id",m.tenant_id).in("hub_object_id",ids);
 if(sourceError)return Response.json({error:"Kunde inte kontrollera urvalet"},{status:500});
 const valid=new Set((sources||[]).filter((x:any)=>x.cost_status==="manual_review").map((x:any)=>x.hub_object_id));
 const failed:{id:string;error:string}[]=[];let succeeded=0;
 for(const item of items){
  if(!valid.has(item.id)){failed.push({id:item.id,error:"Inte längre öppen eller saknar behörighet"});continue;}
  const {error}=await s.from("kpi_bsmart_cost_reviews").upsert({tenant_id:m.tenant_id,hub_object_id:item.id,status:body.status,corrected_cost_sek:body.status==="approved"?item.correctedCost:null,note:body.note.trim(),reviewed_by:user.id,reviewed_at:new Date().toISOString()},{onConflict:"tenant_id,hub_object_id"});
  if(error)failed.push({id:item.id,error:error.message});else succeeded++;
 }
 return Response.json({succeeded,failed});
}