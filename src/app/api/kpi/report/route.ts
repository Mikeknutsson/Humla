import {NextRequest,NextResponse} from 'next/server';
import {loadKpiPeriod} from '@/lib/kpi/live-report';

export async function POST(request:NextRequest) {
 // Only same-origin reads may update the user's saved selection cookie.
 const origin=request.headers.get('origin');
 if(origin&&origin!==request.nextUrl.origin)return NextResponse.json({error:'Ogiltig begäran.'},{status:403});
 try{
  const body=await request.json();
  if(typeof body.query!=='string')return NextResponse.json({error:'Ogiltigt urval.'},{status:400});
  return NextResponse.json(await loadKpiPeriod(body.query),{headers:{'Cache-Control':'private, no-store'}});
 }catch{
  return NextResponse.json({error:'Rapporten kunde inte hämtas. Tidigare urval visas fortfarande.'},{status:503,headers:{'Cache-Control':'private, no-store'}});
 }
}
