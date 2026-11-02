import {createClient} from '@/lib/supabase/server';
import {paymentForecast,type ForecastInput} from '@/lib/hub/payment-forecast';
import {outcomeForecast,type OutcomeSource} from '@/lib/hub/payment-outcome-forecast';
import {periodFingerprints,validatePeriodReviews,periodReviewBasis} from '@/lib/hub/payment-period-review';
import type {PayrollSource} from '@/lib/hub/payment-payroll-forecast';
import {paymentSourceSession,invalidatePaymentSourceSessions} from '@/lib/hub/payment-source-session';
export const dynamic='force-dynamic';
export const runtime='nodejs';
export const maxDuration=180;
class ForecastSourceError extends Error{}
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
  if(body.action==='review-period'){
   if(!member||typeof body.reviewed!=='boolean'||typeof body.month!=='string'||!/^\d{4}-\d{2}-01$/.test(body.month)||!['ordinary','stena'].includes(body.scope)||!['20','30','40'].includes(body.center)||!['in','out'].includes(body.kind)||(body.center==='40'&&body.kind==='in')||(body.scope==='stena'&&body.kind!=='in')||typeof(body.note??'')!=='string'||(body.note??'').length>500)return Response.json({error:'Ogiltig månadsavstämning'},{status:400});
   let fingerprint:string|null=null;
   if(body.reviewed){
    if(typeof body.sourceHash!=='string'||!/^[a-f0-9]{64}$/.test(body.sourceHash))return Response.json({error:'Hämta prognosunderlaget igen före avstämningen.'},{status:400});
    const {data:current,error:sourceError}=await db.rpc('hub_payment_outcome_source_v1',{p_tenant_id:member.tenant_id,p_as_of:new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())});
    if(sourceError||!current)return Response.json({error:'Aktuellt underlag kunde inte kontrolleras. Ingen avstämning har sparats.'},{status:503});
    fingerprint=periodFingerprints(current.rows)(body.scope,body.center,body.kind,body.month);
    if(fingerprint!==body.sourceHash)return Response.json({error:'Underlaget har ändrats efter hämtningen. Hämta och kontrollera månaden igen innan du markerar den som avstämd.'},{status:409});
   }
   const {data,error}=await db.rpc('hub_payment_forecast_reviews_v2',{p_tenant:member.tenant_id,p_scope:body.scope,p_center:body.center,p_kind:body.kind,p_month:body.month,p_reviewed:body.reviewed,p_note:body.note??'',p_source_hash:fingerprint});
   if(error)return Response.json({error:'Avstämningen kunde inte sparas. Välj en avslutad månad och kontrollera underlaget.'},{status:400});
   invalidatePaymentSourceSessions(member.tenant_id);
   return Response.json(data,{headers:{'Cache-Control':'no-store'}});
  }
  if(body.action==='set-one-off'){
   if(!member||!Array.isArray(body.rowIds)||!body.rowIds.length||body.rowIds.length>200||body.rowIds.some((id:unknown)=>typeof id!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id))||typeof body.excluded!=='boolean')return Response.json({error:'Ogiltigt radurval'},{status:400});
   const {data,error}=await db.rpc('hub_payment_forecast_set_exclusion_v1',{p_tenant_id:member.tenant_id,p_rows:body.rowIds,p_excluded:body.excluded,p_note:body.note??''});
   if(error)return Response.json({error:'Markeringen kunde inte sparas.'},{status:400});
   invalidatePaymentSourceSessions(member.tenant_id);
   return Response.json(data,{headers:{'Cache-Control':'no-store'}});
  }
  if(body.mode==='automatic'){
   if(!member)throw Error('Arbetsyta saknas');
   const [snapshot,reviews]=await Promise.all([
    paymentSourceSession(`${member.tenant_id}:${user.id}:${body.asOf}`,body.reuseSource===true,async()=>{
     const [{data,error},salary]=await Promise.all([
      db.rpc('hub_payment_outcome_source_v1',{p_tenant_id:member.tenant_id,p_as_of:body.asOf}),
      db.rpc('hub_payment_payroll_source_v1',{p_tenant_id:member.tenant_id,p_as_of:body.asOf})
     ]);
     if(error||!data)throw new ForecastSourceError('Workify/NeXT-underlaget kunde inte hämtas från Hubben.');
     if(salary.error||!salary.data)throw new ForecastSourceError('TransPA-löneunderlaget kunde inte hämtas från Hubben.');
     if(data.controls?.scope!=='live_approved_imports'&&data.synced_at!==salary.data.synced_at)throw new ForecastSourceError('Hubben uppdaterades under hämtningen. Hämta underlaget igen.');
     return {source:data as OutcomeSource,payroll:salary.data as PayrollSource};
    }),
    db.rpc('hub_payment_forecast_reviews_v2',{p_tenant:member.tenant_id})
   ]);
   if(reviews.error||!reviews.data)return Response.json({error:'Månadsavstämningarna kunde inte hämtas. Försök igen.'},{status:503});
   const data=snapshot.source;
   const forecast=outcomeForecast({...data,periodReviews:validatePeriodReviews(data.rows,reviews.data.reviews),reviewBasis:periodReviewBasis(data.rows,body.asOf)},body.asOf,body.supplierDays??30,body.periodOffset??0,snapshot.payroll);
   return Response.json({...forecast,automatic:{...forecast.automatic,sourceFetchedAt:snapshot.fetchedAt,sourceReused:snapshot.reused}},{headers:{'Cache-Control':'no-store'}});
  }
  return Response.json(paymentForecast(body as ForecastInput),{headers:{'Cache-Control':'no-store'}});
 }catch(e){return Response.json({error:e instanceof Error?e.message:'Ogiltigt underlag'},{status:e instanceof ForecastSourceError?503:400})}
}
