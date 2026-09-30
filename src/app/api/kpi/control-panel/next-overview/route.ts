import {createClient} from "@/lib/supabase/server";
export async function GET(){
 const s=await createClient();
 const {data:{user}}=await s.auth.getUser();
 if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data,error}=await s.rpc("kpi_next_cost_overview");
 if(error)return Response.json({error:error.message},{status:403});
 return Response.json(data,{headers:{"Cache-Control":"no-store"}});
}