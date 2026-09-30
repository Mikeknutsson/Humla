import {createClient} from "@/lib/supabase/server";
export async function POST(req:Request){
 const s=await createClient();
 const {data:{user}}=await s.auth.getUser();
 if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data:m}=await s.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").maybeSingle();
 if(!m)return Response.json({error:"Organisation saknas"},{status:403});
 const {data:allowed}=await s.rpc("hub_has_permission",{p_tenant_id:m.tenant_id,p_permission:"kpi.manage"});
 if(!allowed)return Response.json({error:"Behörighet saknas"},{status:403});
 const b=await req.json().catch(()=>null);
 if(!b||!Array.isArray(b.ids)||!b.ids.length||b.ids.length>50||!["vehicle","project","shared","other"].includes(b.target)||typeof b.reference!=="string"||typeof b.note!=="string"||b.note.trim().length<3)return Response.json({error:"Ogiltigt urval eller klassificering"},{status:400});
 const {data:rows,error}=await s.from("kpi_import_rows").select("id").eq("tenant_id",m.tenant_id).eq("data_kind","cost").eq("is_valid",false).in("id",b.ids as string[]);
 if(error)return Response.json({error:error.message},{status:500});
 const ids: string[] = b.ids as string[];\n const permitted=new Set<string>((rows??[]).map(r=>r.id));
 const failed:{id:string,error:string}[]=[];let succeeded=0;
 for(const id of [...new Set<string>(ids)]){
  if(!permitted.has(id)){failed.push({id,error:"Raden är inte öppen"});continue;}
  const {error:e}=await s.rpc("kpi_classify_next_cost",{p_row_id:id,p_target:b.target,p_reference:b.reference,p_reason:b.note});
  if(e)failed.push({id,error:e.message});else succeeded++;
 }
 return Response.json({succeeded,failed});
}