import {createClient} from '@/lib/supabase/server';
import {revalidateTag} from 'next/cache';
export const dynamic='force-dynamic';
export async function POST(request:Request){
 const db=await createClient();const {data:{user},error:authError}=await db.auth.getUser();
 if(authError||!user)return Response.json({error:'Inloggning krävs.'},{status:401});
 const {data:member,error:memberError}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').maybeSingle();
 if(memberError||!member)return Response.json({error:'Aktiv arbetsyta saknas.'},{status:403});
 try{
 const rule:unknown=await request.json();if(!rule||Array.isArray(rule)||typeof rule!=='object')return Response.json({error:'Ogiltigt regelunderlag.'},{status:400});
 const {data,error}=await db.rpc('hub_allocation_rule_confirm_v2',{p_tenant_id:member.tenant_id,p_rule:rule});
 if(error)return Response.json({error:error.message},{status:error.code==='42501'?403:409});
 revalidateTag(`kpi-report:${user.id}`,{expire:0});return Response.json(data,{headers:{'Cache-Control':'no-store'}});
 }catch{return Response.json({error:'Ogiltigt regelunderlag.'},{status:400});}
}
