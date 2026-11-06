import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import {readSavedSelection,restoreSelection,selectionCookie,selectionFromQuery} from '@/lib/kpi/selection';

export async function proxy(request: NextRequest) {
  // Support Auth's configured site-URL fallback without loading a report first.
  if (request.method === 'GET' && request.nextUrl.searchParams.has('code') && ['/', '/kpi', '/kpi/login'].includes(request.nextUrl.pathname)) {
    const target = request.nextUrl.clone();
    target.pathname = '/kpi/login/confirm';
    target.search = '';
    target.searchParams.set('code', request.nextUrl.searchParams.get('code')!);
    const response = NextResponse.redirect(target);
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('Referrer-Policy', 'no-referrer');
    return response;
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) return NextResponse.next({ request });
  let response = NextResponse.next({ request });
  const supabase = createServerClient(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (cookies) => {
        cookies.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookies.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });
  const {data}=await supabase.auth.getClaims();
  const userId=data?.claims?.sub;
  const path=request.nextUrl.pathname;
  if(userId&&(path==='/kpi'||path.startsWith('/kpi/'))&&!path.startsWith('/kpi/login')&&request.method==='GET'&&!request.headers.has('next-router-prefetch')){
    const name=selectionCookie(userId);
    const saved=readSavedSelection(request.cookies.get(name)?.value);
    const restored=restoreSelection(request.nextUrl.searchParams,saved);
    if(restored){
      const target=request.nextUrl.clone();target.search=restored.toString();
      const redirected=NextResponse.redirect(target);
      response.cookies.getAll().forEach(cookie=>redirected.cookies.set(cookie));
      return redirected;
    }
    if(request.nextUrl.searchParams.get('view')!=='internal'&&['fiscal_year','months','from','to'].some(k=>request.nextUrl.searchParams.has(k))){
      const value=JSON.stringify({version:1,query:selectionFromQuery(request.nextUrl.searchParams).toString()});
      if(readSavedSelection(value)&&request.cookies.get(name)?.value!==value)response.cookies.set(name,value,{httpOnly:true,secure:request.nextUrl.protocol==='https:',sameSite:'lax',path:'/',maxAge:31536000});
    }
  }
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"],
};
