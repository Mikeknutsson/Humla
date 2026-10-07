import {createClient} from '@/lib/supabase/server';
import {revalidateTag} from 'next/cache';
export async function POST(request:Request){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return Response.json({error:'Inloggning krävs'},{status:401});
 const {data:m}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();if(!m)return Response.json({error:'Arbetsyta saknas'},{status:403});
 try{const b=await request.json();if(!/^[0-9a-f-]{36}$/i.test(b.id??'')||!Number.isInteger(b.revision)||typeof b.preview!=='boolean'||typeof b.reason!=='string'||b.reason.trim().length<5||b.reason.length>500||!/^\d{4}-\d{2}-\d{2}$/.test(b.from??''))throw Error('Kontrollera enhet, datum och motivering.');
 const {data,error}=await db.rpc('hub_kpi_complete_unit_history_v1',{p_tenant_id:m.tenant_id,p_unit_id:b.id,p_revision:b.revision,p_from:b.from,p_reason:b.reason,p_preview:b.preview,p_signature:b.signature??null,p_references:b.references??null});
 if(error)return Response.json({error:error.message},{status:400});if(!b.preview)revalidateTag('kpi-report:'+user.id,{expire:0});return Response.json(data);
 }catch(e){return Response.json({error:e instanceof Error?e.message:'Kunde inte komplettera historiken'},{status:400});}
}
