import {createHash} from 'node:crypto';
import {createClient} from '@/lib/supabase/server';
import {parseAccountingReference} from '@/lib/kpi/accounting-reference';
import {managementRange} from '@/lib/kpi/management-period';
import {previousYearDate} from '@/lib/kpi/period';
export const runtime='nodejs';export const maxDuration=60;
export async function POST(request:Request){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:'Inloggning krävs.'},{status:401});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return Response.json({error:'Arbetsyta saknas.'},{status:403});
 const {data:allowed,error:accessError}=await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.manage'});
 if(accessError||!allowed)return Response.json({error:'KPI-administratör krävs för att spara bokföringsunderlag.'},{status:403});
 try{
  const form=await request.formData(),file=form.get('file');
  if(!(file instanceof File)||file.size>3_000_000||!file.name.toLowerCase().endsWith('.xlsx'))throw Error('Välj en Excel-export (.xlsx), högst 3 MB.');
  const bytes=new Uint8Array(await file.arrayBuffer()),source=parseAccountingReference(bytes);
  managementRange(source.from,source.to);
  const {data,error}=await db.rpc('hub_kpi_save_accounting_reference_v1',{p_tenant_id:member.tenant_id,p_from:source.from,p_to:source.to,p_cost_center:source.cost_center,p_source:{...source,file_name:file.name,sha256:createHash('sha256').update(bytes).digest('hex')},p_original:Buffer.from(bytes).toString('base64')});
  if(error){console.error('[monthly reference]',{code:error.code});return Response.json({error:'Bokföringsunderlaget kunde inte sparas i Hubben.'},{status:503});}
  let previousSaved=false;
  if(source.metrics.revenue.previous!=null&&source.metrics.result.previous!=null){
   const from=previousYearDate(source.from),to=previousYearDate(source.to);
   const metrics=Object.fromEntries(Object.entries(source.metrics).filter(([,m])=>m.previous!=null).map(([key,m])=>[key,{...m,value:m.previous,previous:null}]));
   const previous=await db.rpc('hub_kpi_save_accounting_reference_v1',{p_tenant_id:member.tenant_id,p_from:from,p_to:to,p_cost_center:source.cost_center,p_source:{...source,from,to,metrics,source_column:'Föreg års utfall TD',notes:'Jämförelsetal från kolumnen Föreg års utfall TD i samma export. Huvudrader används en gång.',file_name:file.name,sha256:createHash('sha256').update(bytes).digest('hex')},p_original:Buffer.from(bytes).toString('base64')});
   previousSaved=!previous.error;
  }
  return Response.json({saved:true,previous_saved:previousSaved,reference:data,from:source.from,to:source.to,cost_center:source.cost_center});
 }catch(e){return Response.json({error:e instanceof Error?e.message:'Exporten kunde inte läsas.'},{status:400});}
}
