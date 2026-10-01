import {createClient} from '@/lib/supabase/server';
import {analysisQuery,type Analysis} from '@/lib/kpi/analysis';
import {excelExport,pdfExport} from '@/lib/kpi/export';
export const runtime='nodejs';export const maxDuration=60;
export async function GET(req:Request){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return Response.json({error:'Inloggning krävs'},{status:401});
 const {data:m}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();if(!m)return Response.json({error:'Arbetsyta saknas'},{status:403});
 try{const params=new URL(req.url).searchParams;const args=analysisQuery(params);const format=params.get('format');if(!['xlsx','pdf'].includes(format??''))return Response.json({error:'Välj Excel eller PDF'},{status:400});
 const {data,error}=await db.rpc('hub_kpi_analysis_v2',{p_tenant_id:m.tenant_id,...args,p_export:true});if(error)return Response.json({error:'Exportunderlaget kunde inte läsas.'},{status:403});const report=data as Analysis;
 if(report.export_limit_exceeded)return Response.json({error:'Välj ett mindre intervall. Exporten omfattar högst 50 000 transaktioner och inga rader kapas tyst.'},{status:413});
 const context={Från:args.p_from,Till:args.p_to,Nivå:args.p_level,Tid:args.p_grain,Filter:args.p_filters};const bytes=format==='xlsx'?excelExport(report,context):await pdfExport(report,context);
 return new Response(new Uint8Array(bytes),{headers:{'Content-Type':format==='xlsx'?'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':'application/pdf','Content-Disposition':`attachment; filename="humla-kpi-${args.p_from}-${args.p_to}.${format}"`,'Cache-Control':'private, no-store'}});
 }catch{return Response.json({error:'Ogiltig exportförfrågan.'},{status:400})}
}
