import {createClient} from "@/lib/supabase/server";
const connection="e4f21b74-de8a-4c15-8684-2863730c2413";
export async function POST(req:Request){
 const s=await createClient();const {data:{user}}=await s.auth.getUser();
 if(!user)return Response.json({error:"Inloggning krävs"},{status:401});
 const {data:member}=await s.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").maybeSingle();
 if(!member)return Response.json({error:"Organisation saknas"},{status:403});
 const {data:allowed}=await s.rpc("hub_has_permission",{p_tenant_id:member.tenant_id,p_permission:"hub.connections.manage"});
 if(!allowed)return Response.json({error:"Behörighet saknas"},{status:403});
 const {action}=await req.json();if(!["vehicles","units","odometer_readings"].includes(action))return Response.json({error:"Ogiltig åtgärd"},{status:400});
 const {data:session}=await s.auth.getSession();if(!session.session?.access_token)return Response.json({error:"Session saknas"},{status:401});
 const base=process.env.NEXT_PUBLIC_SUPABASE_URL;if(!base)return Response.json({error:"Supabase URL saknas"},{status:500});
 const response=await fetch(base+"/functions/v1/fordonskontrollen-sync",{method:"POST",headers:{"Authorization":"Bearer "+session.session.access_token,"Content-Type":"application/json"},body:JSON.stringify({connection_id:connection,action,mode:"full"}),cache:"no-store"});
 const body=await response.text();let data;try{data=JSON.parse(body)}catch{data={error:body.slice(0,500)}}
 return Response.json(data,{status:response.status});
}