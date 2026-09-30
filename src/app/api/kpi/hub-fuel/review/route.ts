import {createClient} from "@/lib/supabase/server";
export async function POST(req:Request){
 const s=await createClient();const {data:{user}}=await s.auth.getUser();
 if(!user)return Response.json({error:"Login required"},{status:401});
 const {data:m}=await s.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").maybeSingle();
 if(!m)return Response.json({error:"No tenant"},{status:403});
 const {data:ok}=await s.rpc("hub_has_permission",{p_tenant_id:m.tenant_id,p_permission:"kpi.manage"});
 if(!ok)return Response.json({error:"Permission denied"},{status:403});
 const body=await req.json().catch(()=>({}));
 const {id,status,note}=body;const cost=body.correctedCost;
 if(typeof id!=="string"||!["approved","rejected"].includes(status)||typeof note!=="string"||note.trim().length<3||cost!==null&&cost!==undefined&&(typeof cost!=="number"||!Number.isFinite(cost)||cost<=0))return Response.json({error:"Invalid review"},{status:400});
 const {data:source}=await s.from("kpi_bsmart_fuel_checked_v1").select("hub_object_id").eq("tenant_id",m.tenant_id).eq("hub_object_id",id).maybeSingle();
 if(!source)return Response.json({error:"Transaction not found"},{status:404});
 if(status==="approved"&&cost==null)return Response.json({error:"Ange korrigerad totalkostnad innan godkännande"},{status:400});
 const {error}=await s.from("kpi_bsmart_cost_reviews").upsert({tenant_id:m.tenant_id,hub_object_id:id,status,corrected_cost_sek:cost??null,note:note.trim(),reviewed_by:user.id,reviewed_at:new Date().toISOString()},{onConflict:"tenant_id,hub_object_id"});
 if(error)return Response.json({error:error.message},{status:400});
 return Response.json({ok:true});
}