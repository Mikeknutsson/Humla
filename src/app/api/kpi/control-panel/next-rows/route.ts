import {createClient} from "@/lib/supabase/server";
export async function GET(req:Request){
 const s=await createClient();const {data:{user}}=await s.auth.getUser();
 if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data:m}=await s.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").maybeSingle();
 if(!m)return Response.json({error:"Organisation saknas"},{status:403});
 const {data:allowed}=await s.rpc("hub_has_permission",{p_tenant_id:m.tenant_id,p_permission:"kpi.manage"});
 if(!allowed)return Response.json({error:"Behörighet saknas"},{status:403});
 const url=new URL(req.url),batch=url.searchParams.get("batch");
 const page=Math.max(0,Math.min(1000,Number(url.searchParams.get("page"))||0));
 if(!batch)return Response.json({error:"Import saknas"},{status:400});
 const {data:found}=await s.from("kpi_import_batches").select("id").eq("tenant_id",m.tenant_id).eq("id",batch).eq("data_kind","cost").maybeSingle();
 if(!found)return Response.json({error:"Import saknas"},{status:404});
 const {data,error,count}=await s.from("kpi_import_rows").select("id,row_number,occurred_on,project_reference,account,description,amount,vehicle_registration,validation_errors,allocation",{count:"exact"}).eq("tenant_id",m.tenant_id).eq("batch_id",batch).eq("is_valid",false).order("row_number").range(page*50,page*50+49);
 if(error)return Response.json({error:error.message},{status:500});
 return Response.json({rows:data??[],total:count??0});
}