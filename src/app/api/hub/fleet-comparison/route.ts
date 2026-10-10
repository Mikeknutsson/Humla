import {createClient} from '@/lib/supabase/server';
export async function POST(req:Request){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:'Inloggning krävs'},{status:401});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return Response.json({error:'Organisation saknas'},{status:403});
 let body;try{body=await req.json();}catch{return Response.json({error:'Ogiltigt underlag'},{status:400});}
 if(!body||typeof body.name!=='string'||typeof body.class!=='string'||!Array.isArray(body.members)||body.members.some((id:unknown)=>typeof id!=='string'||! /^[0-9a-f-]{36}$/i.test(id))||body.members.length>100)return Response.json({error:'Ogiltig grupp'},{status:400});
 const {data,error}=await db.rpc('hub_fleet_comparison_save_v1',{p_tenant:member.tenant_id,p_group:body.id||null,p_name:body.name,p_class:body.class,p_members:body.members,p_notes:body.notes||'',p_revision:body.revision??null});
 if(error)return Response.json({error:error.code==='42501'?'Behörighet saknas':error.message},{status:error.code==='42501'?403:400});
 return Response.json({id:data});
}
