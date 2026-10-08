import {createClient} from "@/lib/supabase/server";
export const dynamic="force-dynamic";
export async function GET(request:Request){
 const s=await createClient();const {data:{user}}=await s.auth.getUser();
 if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data:m}=await s.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").maybeSingle();
 if(!m)return Response.json({error:"Ingen aktiv organisation"},{status:403});
 const {data:allowed}=await s.rpc("hub_has_permission",{p_tenant_id:m.tenant_id,p_permission:"kpi.manage"});
 if(!allowed)return Response.json({error:"Adminbehörighet krävs"},{status:403});
 const u=new URL(request.url),offset=Math.max(0,Number(u.searchParams.get("offset")||0)||0);
 const {data,error}=await s.rpc("hub_identity_register_admin_v1",{p_tenant_id:m.tenant_id,p_type:u.searchParams.get("type")||null,p_search:u.searchParams.get("search")||null,p_limit:100,p_offset:offset});
 if(error)return Response.json({error:error.message},{status:500});
 return Response.json(data,{headers:{"Cache-Control":"no-store"}});
}