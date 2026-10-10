import {createClient} from '@/lib/supabase/server';
export async function POST(req:Request){
 if(req.headers.get('origin')!==new URL(req.url).origin)return Response.json({error:'Ogiltig förfrågan.'},{status:403});
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:'Logga in igen.'},{status:401});
 const {data:member,error:memberError}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(memberError||!member)return Response.json({error:'Arbetsytan kunde inte öppnas.'},{status:403});
 try{
  if(Number(req.headers.get('content-length')??0)>25000)return Response.json({error:'Underlaget är för stort.'},{status:400});
  const body=await req.json();
  if(!body||!['ownership','comparable','remove_comparable','valuation','accept_estimate','market_context'].includes(body.action)||typeof body.asset_id!=='string'||!/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/.test(body.asset_id)||JSON.stringify(body.data).length>20000)return Response.json({error:'Kontrollera uppgifterna.'},{status:400});
  const {data,error}=body.action==='market_context'?await db.rpc('hub_market_context_save_v1',{p_tenant:member.tenant_id,p_asset:body.asset_id,p_data:body.data}):await db.rpc('hub_asset_tco_save_v1',{p_tenant_id:member.tenant_id,p_asset:body.asset_id,p_action:body.action,p_data:body.data});
  if(error){const message=error.code==='42501'?'Behörighet att hantera fordon saknas.':error.code==='23505'?'Detta jämförelseobjekt finns redan.':error.code==='P0001'?error.message:'Kontrollera datum, pris och obligatoriska uppgifter.';return Response.json({error:message},{status:error.code==='42501'?403:400});}
  return Response.json(data);
 }catch{return Response.json({error:'Underlaget kunde inte sparas. Kontrollera uppgifterna.'},{status:400});}
}
