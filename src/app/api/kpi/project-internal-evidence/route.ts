import {createClient} from '@/lib/supabase/server';
import {internalQuery,type InternalRow} from '@/lib/kpi/internal-transfers';
import type {ProjectReport} from '@/lib/hub/project-report';
export const maxDuration=60;
export async function GET(req:Request){
 const headers={'Cache-Control':'private, no-store'},db=await createClient(),{data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:'Inloggning krävs.'},{status:401,headers});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return Response.json({error:'Arbetsyta saknas.'},{status:403,headers});
 const q=new URL(req.url).searchParams,project=q.get('project');
 try{
  if(!project||! /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(project))throw Error('project');
  const period=internalQuery(q);
  const {data:report,error:reportError}=await db.rpc('hub_kpi_project_report_v4',{p_tenant_id:member.tenant_id,p_from:period.p_from,p_to:period.p_to,p_project:project});
  if(reportError)return Response.json({error:'Projektunderlaget kunde inte läsas.'},{status:reportError.code==='42501'?403:503,headers});
  const selected=(report as ProjectReport).projects.find(p=>p.id===project);
  if(!selected)return Response.json({error:'Projektet finns inte i projektregistret.'},{status:404,headers});
  const {data,error}=await db.rpc('hub_kpi_internal_transfers_v1',{p_tenant_id:member.tenant_id,...period});
  if(error)return Response.json({error:'Internunderlaget kunde inte läsas. Välj en kortare period och försök igen.'},{status:error.code==='42501'?403:503,headers});
  const costRows=new Map((report as ProjectReport).internal_workify_rows.map(r=>[r.id,r]));
  const rows=(data.rows as InternalRow[]).filter(r=>r.project===selected.project_number).map(r=>({id:r.row_id,date:r.occurred_on,order:r.order,article:r.article,description:r.description,amount:r.amount,charged:costRows.get(r.row_id)?.charged??null,included_cost:costRows.has(r.row_id),source_center:r.source_center,receiver_center:r.receiver_center,ready:r.ready,status:r.status,review_reason:r.review_reason}));
  return Response.json({rows},{headers});
 }catch{return Response.json({error:'Välj ett projekt och högst ett verksamhetsår.'},{status:400,headers});}
}
