import {NextRequest,NextResponse} from 'next/server';
import {createClient} from '@/lib/supabase/server';
export async function GET(request:NextRequest){
 const code=request.nextUrl.searchParams.get('code');
 const hash=request.nextUrl.searchParams.get('token_hash');
 const type=request.nextUrl.searchParams.get('type');
 const supabase=await createClient();
 const result=code?await supabase.auth.exchangeCodeForSession(code):hash&&['email','magiclink','invite','recovery'].includes(type??'')?await supabase.auth.verifyOtp({token_hash:hash,type:type as 'email'|'magiclink'|'invite'|'recovery'}):null;
 const target=new URL('/kpi/login/password',request.url);
 if(!result||result.error){target.pathname='/kpi/login/access';target.searchParams.set('error','Länken har gått ut eller kunde inte verifieras. Begär en ny länk och öppna den i samma webbläsare.');}
 const response=NextResponse.redirect(target);response.headers.set('Cache-Control','no-store');response.headers.set('Referrer-Policy','no-referrer');return response;
}
