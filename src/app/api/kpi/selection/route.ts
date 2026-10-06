import {NextRequest,NextResponse} from 'next/server';
import {createClient} from '@/lib/supabase/server';
import {selectionCookie,selectionFromQuery,readSavedSelection} from '@/lib/kpi/selection';

export async function POST(request:NextRequest){
 const origin=request.headers.get('origin');
 if(origin&&origin!==request.nextUrl.origin)return NextResponse.json({error:'Ogiltig begäran.'},{status:403});
 try{
  const body=await request.json();
  if(typeof body.query!=='string'||body.query.length>4000)return NextResponse.json({error:'Ogiltigt urval.'},{status:400});
  const saved=JSON.stringify({version:1,query:selectionFromQuery(new URLSearchParams(body.query)).toString()});
  if(!readSavedSelection(saved))return NextResponse.json({error:'Ogiltigt urval.'},{status:400});
  const db=await createClient();const {data,error}=await db.auth.getClaims();
  const userId=data?.claims?.sub;
  if(error||!userId)return NextResponse.json({error:'Logga in igen.'},{status:401});
  const response=NextResponse.json({saved:true},{headers:{'Cache-Control':'private, no-store'}});
  response.cookies.set(selectionCookie(userId),saved,{httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'lax',path:'/',maxAge:31536000});
  return response;
 }catch{return NextResponse.json({error:'Urvalet kunde inte sparas.'},{status:400});}
}
