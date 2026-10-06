import {createClient} from '@/lib/supabase/server';
import {cachedKpiReport} from '@/lib/kpi/report-cache';
import {parseMonthPeriod} from '@/lib/kpi/period';
import {monthlyExcel,monthlyPdf} from '@/lib/kpi/monthly-report-export';
import type {MonthlyTransportReport} from '@/lib/kpi/monthly-report';
export const runtime='nodejs';export const maxDuration=60;
export async function GET(request:Request){
 const db=await createClient();const {data:claims,error:authError}=await db.auth.getClaims();const userId=claims?.claims?.sub;
 if(authError||!userId)return Response.json({error:'Inloggning krävs.'},{status:401});
 const {data:member,error:memberError}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',userId).eq('status','active').limit(1).maybeSingle();
 if(memberError||!member)return Response.json({error:'Arbetsyta saknas.'},{status:403});
 const {data:allowed,error:permissionError}=await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.read'});
 if(permissionError||!allowed)return Response.json({error:'KPI-behörighet krävs.'},{status:403});
 const params=new URL(request.url).searchParams;
 let year:number,month:number;
 try{const period=parseMonthPeriod(params.get('fiscal_year')??undefined,params.get('report_month')??undefined);if(period.months.length!==1)throw Error();year=period.fiscalYear;month=period.months[0];}catch{return Response.json({error:'Välj en månad och ett giltigt verksamhetsår.'},{status:400});}
 const format=params.get('format');if(format&&!['xlsx','pdf'].includes(format))return Response.json({error:'Ogiltigt exportformat.'},{status:400});
 const costCenter=params.get('cost_center')?.trim()||'30';
 if(costCenter.length>100)return Response.json({error:'Ogiltigt kostnadsställe.'},{status:400});
 const filters=Object.fromEntries(['group','unit','vehicle','project'].filter(k=>params.get(k)).map(k=>[k,params.get(k)!]));
 if(JSON.stringify(filters).length>2000)return Response.json({error:'För stort urval.'},{status:400});
 const result=await cachedKpiReport<MonthlyTransportReport>(userId,member.tenant_id,{report:'transport-monthly-v1',year,month,costCenter,filters},async()=>db.rpc('hub_kpi_monthly_transport_report_v1',{p_tenant_id:member.tenant_id,p_fiscal_year:year,p_month:month,p_cost_center:costCenter,p_filters:filters}));
 if(result.error||!result.data){console.error('[kpi monthly] report unavailable',{code:result.error?.code});return Response.json({error:'Månadsrapporten kunde inte hämtas från Hubben. Försök igen.'},{status:503});}
 const report=result.data;
 if(!format)return Response.json(report,{headers:{'Cache-Control':'private, no-store'}});
 try{const bytes=format==='xlsx'?monthlyExcel(report):await monthlyPdf(report);return new Response(new Uint8Array(bytes),{headers:{'Content-Type':format==='xlsx'?'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':'application/pdf','Content-Disposition':`attachment; filename="humla-nyckeltal-transport-${report.period.from.slice(0,7)}.${format}"`,'Cache-Control':'private, no-store'}});}catch{ return Response.json({error:'Rapportfilen kunde inte skapas. Försök igen.'},{status:500});}
}
