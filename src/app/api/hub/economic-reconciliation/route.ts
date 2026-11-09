import {createClient} from '@/lib/supabase/server';
export const dynamic='force-dynamic';
export const maxDuration=120;
export async function GET(request:Request){
 const db=await createClient();const {data:{user},error:authError}=await db.auth.getUser();
 if(authError||!user)return Response.json({error:'Inloggning krävs.'},{status:401});
 const {data:member,error:memberError}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').maybeSingle();
 if(memberError||!member)return Response.json({error:'Aktiv arbetsyta saknas.'},{status:403});
 const p=new URL(request.url).searchParams;const from=p.get('from'),to=p.get('to'),page=Number(p.get('page')??0);
 if(!from||!to||!/^\d{4}-\d{2}-\d{2}$/.test(from)||!/^\d{4}-\d{2}-\d{2}$/.test(to)||!Number.isSafeInteger(page)||page<0)
 return Response.json({error:'Kontrollera period och sida.'},{status:400});
 const candidates=p.get('view')==='candidates';
 const {data,error}=await db.rpc(candidates?'hub_vehicle_allocation_candidates_v2':'hub_kpi_economic_reconciliation_v3',{
 p_tenant_id:member.tenant_id,p_from:from,p_to:to,p_page:page,...(!candidates?{p_filters:{status:p.get('status')??'included'}}:{})});
 if(error)return Response.json({error:error.message},{status:error.code==='42501'?403:400});
 return Response.json(data,{headers:{'Cache-Control':'no-store'}});
}
