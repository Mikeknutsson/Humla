import { createClient } from '@/lib/supabase/server';
export async function GET(request: Request) {
 const supabase = await createClient();
 const { data: { user } } = await supabase.auth.getUser();
 if (!user) return Response.json({ error: 'Inloggning krävs' }, { status: 401 });
 const url = new URL(request.url);
 const batch = url.searchParams.get('batch');
 const page = Math.max(0, Math.floor(Number(url.searchParams.get('page')) || 0));
 if (!batch || !/^[a-f0-9-]{36}$/i.test(batch)) return Response.json({error:'Ogiltig import'}, {status:400});
 if(url.searchParams.get('history')==='1') {
  const {data,error,count}=await supabase.from('kpi_review_events').select('id,reason,created_at,actor,previous,current,kpi_import_rows!inner(batch_id,row_number)',{count:'exact'}).eq('kpi_import_rows.batch_id',batch).order('created_at',{ascending:false}).range(page*50,page*50+49);
  if(error)return Response.json({error:'Historiken kunde inte hämtas'},{status:500});
  return Response.json({rows:data,total:count});
 }
 const { data, error, count } = await supabase.from('kpi_import_rows').select('*', {count:'exact'}).eq('batch_id', batch).eq('is_valid',false).order('row_number').range(page*50,page*50+49);
 if (error) return Response.json({error:'Granskningsraderna kunde inte hämtas'}, {status:500});
 return Response.json({rows:data,total:count});
}

export async function POST(request: Request) {
 const db = await createClient();
 const {data:{user}} = await db.auth.getUser();
 if (!user) return Response.json({error:'Inloggning krävs'}, {status:401});
 try {
  const body = await request.json();
  if (!/^[a-f0-9-]{36}$/i.test(body.id ?? '') || !body.values || typeof body.values !== 'object' || typeof body.reason !== 'string') return Response.json({error:'Ogiltiga uppgifter'}, {status:400});
  const {data,error} = await db.rpc('kpi_approve_review',{p_row_id:body.id,p_values:body.values,p_reason:body.reason});
  if(error) return Response.json({error:error.message}, {status:400});
  return Response.json(data);
 } catch {return Response.json({error:'Kunde inte godkänna raden'}, {status:400});}
}
