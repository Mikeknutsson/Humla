import {createClient} from '@/lib/supabase/server';
import {revalidateTag} from 'next/cache';
export const dynamic='force-dynamic';
export const maxDuration=120;
async function context(){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(!user)return {error:'Inloggning krävs',status:401} as const;
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return {error:'Arbetsyta saknas',status:403} as const;
 const {data:allowed}=await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.manage'});
 if(!allowed)return {error:'KPI-administratör krävs',status:403} as const;
 return {db,tenant:member.tenant_id,userId:user.id};
}
export async function GET(req:Request){
 const c=await context();if('error'in c)return Response.json({error:c.error},{status:c.status});
 const p=new URL(req.url).searchParams;
 const {data,error}=await c.db.rpc(p.get('workspace')==='1'?'hub_kpi_match_queue_v2':'hub_kpi_match_queue_v1',{p_tenant_id:c.tenant,p_from:p.get('from'),p_to:p.get('to'),p_dimension:p.get('dimension')??'cost_center',p_reference_type:p.get('reference_type')??'project',p_search:p.get('search')??'',p_page:Number(p.get('page')??0)});
 if(error)return Response.json({error:error.message},{status:400});
 return Response.json(data,{headers:{'Cache-Control':'no-store'}});
}
export async function POST(req:Request){
 const c=await context();if('error'in c)return Response.json({error:c.error},{status:c.status});
 try{
  const b=await req.json();const {data,error}=b.changes?await c.db.rpc('hub_kpi_match_changes_v1',{p_tenant_id:c.tenant,p_changes:b.changes,p_from:b.from,p_to:b.to,p_reason:b.reason,p_preview:b.preview===true}):await c.db.rpc('hub_kpi_match_save_many_v1',{p_tenant_id:c.tenant,p_items:b.items,p_targets:b.targets??{[b.dimension]:b.target},p_from:b.from,p_to:b.to||null,p_reason:b.reason});
  if(error)return Response.json({error:error.message},{status:400});
  if(b.preview!==true)revalidateTag(`kpi-report:${c.userId}`,{expire:0});
  return Response.json(data);
 }catch{return Response.json({error:'Ogiltigt matchningsunderlag'},{status:400})}
}
