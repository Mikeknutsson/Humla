import {createClient} from '@/lib/supabase/server';
import {paymentForecast,type ForecastInput} from '@/lib/hub/payment-forecast';
import {outcomeForecast,type OutcomeSource} from '@/lib/hub/payment-outcome-forecast';
import type {PayrollSource} from '@/lib/hub/payment-payroll-forecast';
export const dynamic='force-dynamic';
export const runtime='nodejs';
export const maxDuration=60;
export async function POST(req:Request){
 if(req.headers.get('origin')!==new URL(req.url).origin)return Response.json({error:'Ogiltigt ursprung'},{status:403});
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:'Inloggning krävs'},{status:401});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 const {data:allowed}=member?await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.manage'}):{data:false};
 if(!allowed)return Response.json({error:'KPI-administratör krävs för avdelningens betalningsunderlag'},{status:403});
 const text=await req.text();if(text.length>8_000_000)return Response.json({error:'Underlaget är för stort'},{status:413});
 try{
  const body=JSON.parse(text);
  if(body.mode==='automatic'){
   if(!member)throw Error('Arbetsyta saknas');
   const [{data,error},salary]=await Promise.all([
    db.rpc('hub_payment_outcome_source_v1',{p_tenant_id:member.tenant_id,p_as_of:body.asOf}),
    db.rpc('hub_payment_payroll_source_v1',{p_tenant_id:member.tenant_id,p_as_of:body.asOf})
   ]);
   if(error||!data)return Response.json({error:'Workify/NeXT-underlaget kunde inte hämtas från Hubben.'},{status:503});
   if(salary.error||!salary.data)return Response.json({error:'TransPA-löneunderlaget kunde inte hämtas från Hubben.'},{status:503});
   if(data.synced_at!==salary.data.synced_at)return Response.json({error:'Hubben uppdaterades under hämtningen. Hämta underlaget igen.'},{status:503});
   return Response.json(outcomeForecast(data as OutcomeSource,body.asOf,body.supplierDays??30,body.periodOffset??0,salary.data as PayrollSource),{headers:{'Cache-Control':'no-store'}});
  }
  return Response.json(paymentForecast(body as ForecastInput),{headers:{'Cache-Control':'no-store'}});
 }catch(e){return Response.json({error:e instanceof Error?e.message:'Ogiltigt underlag'},{status:400})}
}
