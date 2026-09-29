import { createClient } from '@/lib/supabase/server';
export async function GET(request:Request){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:'Inloggning krävs'},{status:401});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').maybeSingle();
 if(!member)return Response.json({error:'Arbetsyta saknas'},{status:403});
 const q=new URL(request.url).searchParams;
 if(!/^[a-f0-9-]{36}$/i.test(q.get('unit')??'')||!/^\d{4}-\d{2}-\d{2}$/.test(q.get('from')??'')||!/^\d{4}-\d{2}-\d{2}$/.test(q.get('to')??'')||!['year','month','week','day'].includes(q.get('grain')??''))return Response.json({error:'Ogiltigt urval'},{status:400});
 const {data,error}=await db.rpc('kpi_unit_detail',{p_tenant_id:member.tenant_id,p_unit_id:q.get('unit'),p_from:q.get('from'),p_to:q.get('to'),p_grain:q.get('grain'),p_page:Number(q.get('page')??0)});
 if(error)return Response.json({error:'Uppföljningen kunde inte hämtas. Kontrollera datumintervallet (högst tio år).'},{status:400});
 return Response.json(data);
}
