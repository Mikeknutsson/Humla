import {createClient} from '@/lib/supabase/server';
import {cachedKpiReport} from '@/lib/kpi/report-cache';
import {parseMonthPeriod,periodFilters} from '@/lib/kpi/period';
export const maxDuration=60;
export async function GET(request:Request){
 const db=await createClient();const {data:claims}=await db.auth.getClaims();const userId=claims?.claims?.sub;
 if(!userId)return Response.json({error:'Inloggning krävs.'},{status:401});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',userId).eq('status','active').maybeSingle();
 if(!member)return Response.json({error:'Arbetsyta saknas.'},{status:403});
 const {data:allowed}=await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.read'});
 if(!allowed)return Response.json({error:'KPI-behörighet krävs.'},{status:403});
 const p=new URL(request.url).searchParams,part=p.get('part')??'overview';
 if(!['overview','internal','billing','workshop'].includes(part))return Response.json({error:'Ogiltig jämförelse.'},{status:400});
 let period:ReturnType<typeof parseMonthPeriod>;try{period=parseMonthPeriod(p.get('fiscal_year')??undefined,p.get('months')??undefined,new Date(),p.get('period_mode')??undefined);}catch{return Response.json({error:'Ogiltig period.'},{status:400});}
 const filters=periodFilters(period,Object.fromEntries(['cost_center','group','unit','vehicle','project','category','kind','source','date_from','date_to'].filter(k=>p.get(k)).map(k=>[k,p.get(k)!])));
 if(part==='workshop'&&(filters.cost_center!=='40'||Object.keys(filters).some(k=>!['cost_center','date_from','date_to','period_mode'].includes(k))))return Response.json({error:'Verkstadsjämförelsen kräver enbart kostnadsställe 40.'},{status:400});
 // Shift absolute day filters with the fiscal year, including Feb 29 -> Feb 28.
 function previousFilters(){const result={...filters};for(const key of ['date_from','date_to'])if(result[key]){
  const d=new Date(result[key]+'T00:00:00Z');if(!/^\d{4}-\d{2}-\d{2}$/.test(result[key])||!Number.isFinite(d.getTime())||d.toISOString().slice(0,10)!==result[key])throw Error('Ogiltigt datum');
  const month=d.getUTCMonth();d.setUTCFullYear(d.getUTCFullYear()-1);if(d.getUTCMonth()!==month)d.setUTCDate(0);result[key]=d.toISOString().slice(0,10);
 }return result;}
 try{
  const before=previousFilters();
  async function source(year:number,scope:Record<string,string>,sourcePart=part):Promise<Record<string,unknown>|null>{
   const result=await cachedKpiReport<Record<string,unknown>>(userId!,member!.tenant_id,{report:'year-source-v1',part:sourcePart,year,months:period.months,filters:scope},async()=>{
    if(sourcePart==='internal')return db.rpc('hub_kpi_internal_summary_v1',{p_tenant:member!.tenant_id,p_year:year,p_months:period.months,p_filters:scope});
    if(sourcePart==='billing')return db.rpc('hub_kpi_billing_balance_v1',{p_tenant:member!.tenant_id,p_year:year,p_months:period.months,p_filters:Object.fromEntries(Object.entries(scope).filter(([k])=>['cost_center','group','unit','vehicle','project','date_from','date_to','period_mode'].includes(k)))});
    if(sourcePart==='workshop')return db.rpc('hub_kpi_workshop_time_v1',{p_tenant_id:member!.tenant_id,p_from:scope.date_from??`${year}-09-01`,p_to:scope.date_to??`${year+1}-08-31`,p_months:period.months});
    const {cost_center,...rest}=scope;
    return db.rpc('hub_kpi_overview_months_v1',{p_tenant_id:member!.tenant_id,p_fiscal_year:year,p_selected_months:period.months,p_cost_center:cost_center||null,p_filters:rest});
   });
   // Outside prepared history is missing data; other errors remain retryable.
   if(result.error&&result.error.code!=='55000'){console.error('KPI year source failed',{part:sourcePart,code:result.error.code});throw Error('Jämförelseunderlaget kunde inte hämtas.');}
   if(sourcePart!=='overview'&&result.data){
    const coverage=await source(year,scope,'overview');
    return {...result.data,coverage:coverage?.coverage??null};
   }
   return result.data;
  }
  const [current,previous]=await Promise.all([source(period.fiscalYear,filters),source(period.fiscalYear-1,before)]);
  const {data,error}=await db.rpc('hub_kpi_compare_snapshots_v1',{p_tenant:member.tenant_id,p_months:period.months,p_part:part,p_current:current,p_previous:previous});
  if(error||!data){console.error('KPI year comparison failed',{code:error?.code});throw Error('Jämförelsen kunde inte beräknas.');}
  return Response.json({...data,year:period.fiscalYear,previous_year:period.fiscalYear-1,months:period.months},{headers:{'Cache-Control':'private, no-store'}});
 }catch{return Response.json({error:'Årsjämförelsen kunde inte hämtas. Övriga KPI visas fortfarande.'},{status:503});}
}
