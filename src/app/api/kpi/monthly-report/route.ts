import {createClient} from '@/lib/supabase/server';
import {cachedKpiReport} from '@/lib/kpi/report-cache';
import {managementPeriod,previousManagementPeriod,type ManagementPeriod} from '@/lib/kpi/management-period';
import {monthlyExcel} from '@/lib/kpi/monthly-report-export';
import {departmentMonthlyPdf} from '@/lib/kpi/department-monthly-pdf';
import type {MonthlyTransportReport} from '@/lib/kpi/monthly-report';
export const runtime='nodejs';export const maxDuration=120;
export async function GET(request:Request){
 const db=await createClient();const {data:claims,error:authError}=await db.auth.getClaims();const userId=claims?.claims?.sub;
 if(authError||!userId)return Response.json({error:'Inloggning krävs.'},{status:401});
 const {data:member,error:memberError}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',userId).eq('status','active').limit(1).maybeSingle();
 if(memberError||!member)return Response.json({error:'Arbetsyta saknas.'},{status:403});
 const {data:allowed,error:permissionError}=await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.read'});
 if(permissionError||!allowed)return Response.json({error:'KPI-behörighet krävs.'},{status:403});
 const params=new URL(request.url).searchParams;
 let period:ManagementPeriod;
 try{period=managementPeriod(params);}catch(e){return Response.json({error:e instanceof Error?e.message:'Välj en giltig period.'},{status:400});}

 const format=params.get('format');if(format&&!['xlsx','pdf'].includes(format))return Response.json({error:'Ogiltigt exportformat.'},{status:400});
 const costCenter=params.get('cost_center')?.trim()||'30';
 const variant=params.get('variant')==='ledning'?'ledning':'utforlig';
 if(!/^(10|20|30|40|50|60|90)(,(10|20|30|40|50|60|90))*$/.test(costCenter))return Response.json({error:'Ogiltigt kostnadsställe.'},{status:400});
 const filters=Object.fromEntries(['group','unit','vehicle','project'].filter(k=>params.get(k)).map(k=>[k,params.get(k)!]));
 if(JSON.stringify(filters).length>2000)return Response.json({error:'För stort urval.'},{status:400});
 const loadComparable=async(code:string,selectedFilters:Record<string,string>)=>{
  const load=(p:ManagementPeriod)=>cachedKpiReport<MonthlyTransportReport>(userId,member.tenant_id,{report:'management-period-v3-stena-timing',from:p.from,to:p.to,costCenter:code,filters:selectedFilters},async()=>db.rpc('hub_kpi_management_report_v1',{p_tenant_id:member.tenant_id,p_from:p.from,p_to:p.to,p_cost_center:code,p_filters:selectedFilters}));
  const [current,previous]=await Promise.all([load(period),load(previousManagementPeriod(period))]);
  if(current.data&&previous.data&&current.data.generation!==previous.data.generation)return {data:null,error:{code:'GENERATION_CHANGED',message:'Underlaget uppdaterades under hämtningen. Hämta rapporten igen.'}};
  return current.data?{...current,data:{...current.data,previous:previous.data?{period:previous.data.period,month:previous.data.month,ytd:previous.data.ytd}:null,previous_available:!!previous.data}}:current;
 };
 const loadDepartment=(code:string)=>loadComparable(code,filters);
 if(format==='pdf'){
  const departments=[];
  if(costCenter.includes(','))departments.push({code:costCenter,name:'Sammanlagt',result:await loadDepartment(costCenter)});
  for(const code of [...new Set(costCenter.split(','))])departments.push({code,name:({'10':'Entreprenad','20':'Sortergården','30':'Transport','40':'Verkstad','50':'Fastigheter','60':'Skåne','90':'Övrigt'} as Record<string,string>)[code],result:await loadDepartment(code)});
  if(departments.some(d=>d.result.error||!d.result.data))return Response.json({error:'Underlag för samtliga valda avdelningar krävs för PDF-rapporten.'},{status:503});
  try{const bytes=await departmentMonthlyPdf(departments.map(d=>({code:d.code,name:d.name,report:d.result.data!})),variant);return new Response(new Uint8Array(bytes),{headers:{'Content-Type':'application/pdf','Content-Disposition':`attachment; filename="humla-manadsrapport-${variant}-${period.from}-${period.to}.pdf"`,'Cache-Control':'private, no-store'}});}catch{return Response.json({error:'PDF kunde inte skapas.'},{status:500});}
 }
 const result=await loadComparable(costCenter,filters);
 if(result.error||!result.data){console.error('[kpi monthly] report unavailable',{code:result.error?.code});return Response.json({error:'Månadsrapporten kunde inte hämtas från Hubben. Försök igen.'},{status:503});}
 const report=result.data;
 // The browser needs monthly evidence only; full YTD transactions remain server-side for export.
 if(!format)return Response.json({...report,ytd:{...report.ytd,fuel_sources:report.ytd.fuel_sources?{...report.ytd.fuel_sources,transactions:[]}:undefined},previous:report.previous?{...report.previous,month:{...report.previous.month,fuel_sources:report.previous.month.fuel_sources?{...report.previous.month.fuel_sources,transactions:[]}:undefined},ytd:{...report.previous.ytd,fuel_sources:report.previous.ytd.fuel_sources?{...report.previous.ytd.fuel_sources,transactions:[]}:undefined}}:null},{headers:{'Cache-Control':'private, no-store'}});
 try{const bytes=monthlyExcel(report);return new Response(new Uint8Array(bytes),{headers:{'Content-Type':format==='xlsx'?'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':'application/pdf','Content-Disposition':`attachment; filename="humla-ledningsrapport-${period.from}-${period.to}.${format}"`,'Cache-Control':'private, no-store'}});}catch{ return Response.json({error:'Rapportfilen kunde inte skapas. Försök igen.'},{status:500});}
}
