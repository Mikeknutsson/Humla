import {createClient} from "@/lib/supabase/server";
export const dynamic="force-dynamic";
export async function GET(_request:Request,context:{params:Promise<{id:string}>}){
 const {id}=await context.params;
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))return Response.json({error:"Ogiltigt Humla-ID"},{status:400});
 const s=await createClient();const {data:{user}}=await s.auth.getUser();
 if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data:m}=await s.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").maybeSingle();
 if(!m)return Response.json({error:"Ingen aktiv organisation"},{status:403});
 const {data:allowed}=await s.rpc("hub_has_permission",{p_tenant_id:m.tenant_id,p_permission:"kpi.manage"});
 if(!allowed)return Response.json({error:"Adminbehörighet krävs"},{status:403});
 const {data,error}=await s.rpc("hub_identity_detail_admin_v1",{p_tenant_id:m.tenant_id,p_object_id:id});
 if(error)return Response.json({error:error.message},{status:500});
 if(!data)return Response.json({error:"Objektet hittades inte"},{status:404});
 return Response.json(data,{headers:{"Cache-Control":"no-store"}});
}