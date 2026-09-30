import {createClient} from "@/lib/supabase/server";
const escape=(value:unknown)=>'"'+String(value??"").replace(/"/g,'""')+'"';
export async function GET(){
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data:member}=await db.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(!member)return Response.json({error:"Arbetsyta saknas"},{status:403});
 const {data:allowed}=await db.rpc("hub_has_permission",{p_tenant_id:member.tenant_id,p_permission:"kpi.manage"});
 if(!allowed)return Response.json({error:"Behörighet saknas"},{status:403});
 const {data,error}=await db.from("hub_fordonskontrollen_cost_outbox").select("external_reference,external_vehicle_id,occurred_on,amount,account,description,status").eq("tenant_id",member.tenant_id).eq("status","approved").order("occurred_on",{ascending:true}).limit(10000);
 if(error)return Response.json({error:error.message},{status:500});
 const lines=["Humla-referens;Fordonskontrollen fordons-ID;Datum;Belopp;Konto;Beskrivning;Status",...(data??[]).map(r=>[r.external_reference,r.external_vehicle_id,r.occurred_on,r.amount,r.account,r.description,r.status].map(escape).join(";"))];
 const csv="\uFEFF"+lines.join("\r\n");
 return new Response(csv,{headers:{"content-type":"text/csv; charset=utf-8","content-disposition":"attachment; filename=humla-fordonskontrollen-reparationer.csv","cache-control":"no-store"}});
}