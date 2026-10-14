import {NextRequest,NextResponse} from 'next/server';
import {reviewAccess} from '@/lib/hub/review-access';
import {parseMonthPeriod} from '@/lib/kpi/period';
export async function GET(request:NextRequest){
 const access=await reviewAccess();
 if(!access)return NextResponse.json({error:'Åtkomst saknas'},{status:403});
 const p=request.nextUrl.searchParams;
 try{
  const period=p.has('fiscal_year')?parseMonthPeriod(p.get('fiscal_year')!,p.get('months')??undefined):null;
  const from=period?`${period.fiscalYear}-09-01`:p.get('from'),to=period?`${period.fiscalYear+1}-08-31`:p.get('to');
  if(!from||!to||![from,to].every(d=>/^\d{4}-\d{2}-\d{2}$/.test(d)&&!Number.isNaN(Date.parse(d))&&new Date(d).toISOString().slice(0,10)===d))return NextResponse.json({error:'Ogiltig period'},{status:400});
  const r=await access.db.rpc('hub_kpi_workshop_time_v1',{p_tenant_id:access.tenantId,p_from:from,p_to:to,p_months:period?.months??null});
  if(r.error)throw new Error('Workshop time unavailable');
  return NextResponse.json(r.data,{headers:{'Cache-Control':'private, no-store'}});
 }catch{return NextResponse.json({error:'Verkstadstiden kunde inte hämtas'},{status:503});}
}
