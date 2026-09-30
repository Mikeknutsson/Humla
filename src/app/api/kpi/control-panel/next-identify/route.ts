import {createClient} from "@/lib/supabase/server";
export async function POST(){
 const s=await createClient();
 const {data:{user}}=await s.auth.getUser();
 if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data:m}=await s.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").maybeSingle();
 if(!m)return Response.json({error:"Organisation saknas"},{status:403});
 const {data:allowed}=await s.rpc("hub_has_permission",{p_tenant_id:m.tenant_id,p_permission:"kpi.manage"});
 if(!allowed)return Response.json({error:"Behörighet saknas"},{status:403});
 const {data,error}=await s.rpc("kpi_identify_next_costs");
 if(error)return Response.json({error:error.message},{status:400});
 return Response.json(data);
}