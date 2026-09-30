import {createClient} from "@/lib/supabase/server";
export const dynamic="force-dynamic";
export async function GET(){
 const s=await createClient();const {data:{user}}=await s.auth.getUser();
 if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data:m}=await s.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").maybeSingle();
 if(!m)return Response.json({error:"Ingen aktiv organisation"},{status:403});
 const {data:allowed}=await s.rpc("hub_has_permission",{p_tenant_id:m.tenant_id,p_permission:"kpi.manage"});
 if(!allowed)return Response.json({error:"Adminbehörighet krävs"},{status:403});
 const [{data:reviews,error},{data:connections},{data:nextBatches}]=await Promise.all([
 s.from("hub_review_queue").select("id,review_type,activity_kind,severity,reason_code,payload,created_at,blocking").eq("tenant_id",m.tenant_id).eq("status","open").order("created_at",{ascending:false}).limit(500),
 s.from("hub_connections").select("connector_type,status,last_success_at,last_error_at").eq("tenant_id",m.tenant_id),
 s.from("kpi_import_batches").select("id,file_name,status,row_count,valid_row_count,invalid_row_count").eq("tenant_id",m.tenant_id).eq("data_kind","cost").order("created_at",{ascending:false}).limit(20)
 ]);
 if(error)return Response.json({error:error.message},{status:500});
 return Response.json({reviews:reviews??[],connections:connections??[],nextBatches:nextBatches??[]},{headers:{"Cache-Control":"no-store"}});
}