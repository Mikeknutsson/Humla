import {createClient} from '@/lib/supabase/server';
import {revalidateTag} from 'next/cache';
export async function POST(request:Request){
 const origin=request.headers.get('origin');if(origin&&origin!==new URL(request.url).origin)return Response.json({error:'Ogiltig begäran.'},{status:403});
 const db=await createClient();const {data:claims}=await db.auth.getClaims();const userId=claims?.claims?.sub;
 if(!userId)return Response.json({error:'Logga in igen.'},{status:401});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',userId).eq('status','active').maybeSingle();
 if(!member)return Response.json({error:'Arbetsyta saknas.'},{status:403});
 let body;try{body=await request.json();}catch{return Response.json({error:'Ogiltigt underlag.'},{status:400});}
 if(typeof body.month!=='string'||typeof body.center!=='string'||typeof body.management!=='number'||typeof body.other!=='number'||typeof body.evidence!=='string')return Response.json({error:'Fyll i båda beloppen och hänvisningen till underlaget.'},{status:400});
 const {error}=await db.rpc('hub_overhead_month_save_v1',{p_tenant:member.tenant_id,p_month:body.month,p_center:body.center,p_management:body.management,p_other:body.other,p_evidence:body.evidence});
 if(error)return Response.json({error:error.code==='42501'?'Du saknar behörighet att ändra KPI-underlaget.':'Underlaget kunde inte sparas. Kontrollera månad, kostnadsställe och belopp.'},{status:400});
 revalidateTag(`kpi-report:${userId}`,{expire:0});return Response.json({ok:true});
}
