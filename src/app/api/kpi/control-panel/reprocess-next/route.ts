import {createClient} from "@/lib/supabase/server";
export async function POST(req:Request){
 const s=await createClient();const {data:{user}}=await s.auth.getUser();if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data:m}=await s.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").maybeSingle();
 if(!m)return Response.json({error:"Ingen aktiv organisation"},{status:403});
 const {data:ok}=await s.rpc("hub_has_permission",{p_tenant_id:m.tenant_id,p_permission:"kpi.manage"});if(!ok)return Response.json({error:"Behörighet saknas"},{status:403});
 const {batchId}=await req.json().catch(()=>({}));if(typeof batchId!=="string"||!(/^[a-f0-9-]{36}$/i.test(batchId)))return Response.json({error:"Ogiltig import"},{status:400});
 const {data:batch}=await s.from("kpi_import_batches").select("id").eq("id",batchId).eq("tenant_id",m.tenant_id).eq("data_kind","cost").maybeSingle();
 if(!batch)return Response.json({error:"Importen saknas"},{status:404});
 const {data,error}=await s.rpc("kpi_reprocess_next_project_mappings",{p_batch_id:batchId});
 if(error)return Response.json({error:error.message},{status:400});
 return Response.json(data);
}