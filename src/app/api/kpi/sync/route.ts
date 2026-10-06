import {createClient} from '@/lib/supabase/server';
import {getKpiReportStatus} from '@/lib/kpi/report-sync';
export const dynamic='force-dynamic';

export async function GET(){
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:'Inloggning krävs'},{status:401});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return Response.json({error:'Arbetsyta saknas'},{status:403});
 const {data,error}=await getKpiReportStatus(member.tenant_id);
 if(error||!data)return Response.json({error:'Synkstatus kunde inte hämtas'},{status:error?.code==='42501'?403:503});
 return Response.json(data,{headers:{'Cache-Control':'private, no-store'}});
}
