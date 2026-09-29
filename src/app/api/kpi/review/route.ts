import { createClient } from '@/lib/supabase/server';
export async function GET(request: Request) {
 const supabase = await createClient();
 const { data: { user } } = await supabase.auth.getUser();
 if (!user) return Response.json({ error: 'Inloggning krävs' }, { status: 401 });
 const url = new URL(request.url);
 const batch = url.searchParams.get('batch');
 const page = Math.max(0, Math.floor(Number(url.searchParams.get('page')) || 0));
 if (!batch || !/^[a-f0-9-]{36}$/i.test(batch)) return Response.json({error:'Ogiltig import'}, {status:400});
 const { data, error, count } = await supabase.from('kpi_import_rows').select('id,row_number,source_data,validation_errors', {count:'exact'}).eq('batch_id', batch).eq('is_valid',false).order('row_number').range(page*50,page*50+49);
 if (error) return Response.json({error:'Granskningsraderna kunde inte hämtas'}, {status:500});
 return Response.json({rows:data,total:count});
}
