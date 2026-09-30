import {createClient} from "@/lib/supabase/server";
export async function GET(){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data:member}=await db.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(!member)return Response.json({error:"Arbetsyta saknas"},{status:403});
 const {data:allowed}=await db.rpc("hub_has_permission",{p_tenant_id:member.tenant_id,p_permission:"kpi.read"});
 if(!allowed)return Response.json({error:"Behörighet saknas"},{status:403});
 const {data,error}=await db.from("hub_fordonskontrollen_cost_outbox").select("id,external_vehicle_id,occurred_on,amount,account,description,status,external_reference,error_message").eq("tenant_id",member.tenant_id).order("occurred_on",{ascending:false}).limit(500);
 if(error)return Response.json({error:error.message},{status:500});
 return Response.json({rows:data});
}
export async function POST(req:Request){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data:member}=await db.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(!member)return Response.json({error:"Arbetsyta saknas"},{status:403});
 const {data:allowed}=await db.rpc("hub_has_permission",{p_tenant_id:member.tenant_id,p_permission:"kpi.manage"});
 if(!allowed)return Response.json({error:"Behörighet saknas"},{status:403});
 const body=await req.json();
 if(!Array.isArray(body.ids)||body.ids.length<1||body.ids.length>100||!body.ids.every((x:unknown)=>typeof x==="string"&&/^[0-9a-f-]{36}$/i.test(x)))return Response.json({error:"Ogiltiga rader"},{status:400});
 if(!["approved","excluded"].includes(body.status))return Response.json({error:"Ogiltig status"},{status:400});
 const {data,error}=await db.from("hub_fordonskontrollen_cost_outbox").update({status:body.status,approved_by:user.id,approved_at:new Date().toISOString()}).eq("tenant_id",member.tenant_id).eq("status","pending_review").in("id",body.ids).select("id");
 if(error)return Response.json({error:error.message},{status:500});
 return Response.json({updated:data?.length??0,note:"Godkända rader ligger i kö. Ingen överföring till Fordonskontrollen sker förrän skriv-API har verifierats."});
}