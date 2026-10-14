import {createClient} from '@/lib/supabase/server';
import {parseMonthPeriod} from '@/lib/kpi/period';
import {cachedKpiReport} from '@/lib/kpi/report-cache';
import {filterKeys} from '@/lib/kpi/analysis';
export const maxDuration=45;
export async function GET(request:Request){
 const db=await createClient();const {data:claims}=await db.auth.getClaims();const userId=claims?.claims?.sub;
 if(!userId)return Response.json({error:'Inloggning krävs.'},{status:401});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',userId).eq('status','active').maybeSingle();
 if(!member)return Response.json({error:'Arbetsyta saknas.'},{status:403});
 const {data:allowed}=await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.read'});if(!allowed)return Response.json({error:'KPI-behörighet krävs.'},{status:403});
 const p=new URL(request.url).searchParams;
 let period;try{period=parseMonthPeriod(p.get('fiscal_year')??undefined,p.get('months')??undefined);}catch{return Response.json({error:'Ogiltig period.'},{status:400});}
 const filters=Object.fromEntries(filterKeys.filter(k=>p.get(k)).map(k=>[k,p.get(k)!]));
 const result=await cachedKpiReport(userId,member.tenant_id,{report:'internal-summary-v3',year:period.fiscalYear,months:period.months,filters},async()=>db.rpc('hub_kpi_internal_summary_v1',{p_tenant:member.tenant_id,p_year:period.fiscalYear,p_months:period.months,p_filters:filters}));
 return result.error?Response.json({error:'Internt underlag kunde inte hämtas. Ekonomirapporten är fortfarande tillgänglig.'},{status:503}):Response.json(result.data,{headers:{'Cache-Control':'private, no-store'}});
}
