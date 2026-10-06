import { createClient } from '@/lib/supabase/server';
export async function GET(request: Request) {
 const supabase = await createClient();
 const { data: { user } } = await supabase.auth.getUser();
 if (!user) return Response.json({ error: 'Inloggning krävs' }, { status: 401 });
 const url = new URL(request.url);
 if(url.searchParams.get('options')==='1') {
  const {data:member}=await supabase.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
  if(!member)return Response.json({error:'Aktivt företag saknas'},{status:403});
  const {data,error}=await supabase.rpc('hub_kpi_review_options_v1',{p_tenant_id:member.tenant_id});
  if(error)return Response.json({error:'Projekt och fordon kunde inte hämtas'},{status:403});
  return Response.json(data,{headers:{'Cache-Control':'private, max-age=300'}});
 }
 if(url.searchParams.get('scope')) {
  const {data:member}=await supabase.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
  if(!member)return Response.json({error:'Aktivt företag saknas'},{status:403});
  const {data:allowed,error:permissionError}=await supabase.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.read'});
  if(permissionError||!allowed)return Response.json({error:'KPI-behörighet krävs'},{status:403});
  const from=url.searchParams.get('from')??'',to=url.searchParams.get('to')??'',scope=url.searchParams.get('scope');
  const valid=(v:string)=>/^\d{4}-\d{2}-\d{2}$/.test(v)&&Number.isFinite(Date.parse(v))&&new Date(v).toISOString().slice(0,10)===v;
  if(!valid(from)||!valid(to)||to<from||Date.parse(to)-Date.parse(from)>366*86400000||!['period','undated','all'].includes(scope!))return Response.json({error:'Ogiltigt periodurval'},{status:400});
  const page=Math.max(0,Math.floor(Number(url.searchParams.get('page'))||0));
  if(page>10000)return Response.json({error:'Ogiltig sida'},{status:400});
  let query=supabase.from('kpi_import_rows').select('*,kpi_import_batches(file_name)',{count:'exact'}).eq('tenant_id',member.tenant_id).eq('is_valid',false);
  if(scope==='undated')query=query.is('occurred_on',null);
  else if(scope==='period')query=query.or(`occurred_on.is.null,and(occurred_on.gte.${from},occurred_on.lte.${to})`);
  const [rows,all,undated]=await Promise.all([
   query.order('occurred_on',{nullsFirst:false}).order('id').range(page*50,page*50+49),
   supabase.from('kpi_import_rows').select('id',{count:'exact',head:true}).eq('tenant_id',member.tenant_id).eq('is_valid',false),
   supabase.from('kpi_import_rows').select('id',{count:'exact',head:true}).eq('tenant_id',member.tenant_id).eq('is_valid',false).is('occurred_on',null),
  ]);
  if(rows.error||all.error||undated.error)return Response.json({error:'KPI-granskningen kunde inte hämtas'},{status:500});
  return Response.json({rows:rows.data,total:rows.count,all:all.count,undated:undated.count},{headers:{'Cache-Control':'private, no-store'}});
 }
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
  if(body.action==='hub_mapping'){
   const ids=Array.isArray(body.reviewIds)?body.reviewIds:[body.reviewId];
   if(!ids.length||!body.mappingType||!body.sourceValue||!body.destinationValue)return Response.json({error:'Ofullständig mappning'},{status:400});
   const results=[];
   for(const id of ids){const {data,error}=await db.rpc('hub_remember_mapping_v1',{p_review_id:id,p_mapping_type:body.mappingType,p_source_value:body.sourceValue,p_destination_value:body.destinationValue,p_destination_external_id:body.destinationExternalId??null,p_remember:body.remember!==false});if(error)return Response.json({error:error.message},{status:400});results.push(data)}
   return Response.json({ok:true,results});
  }
  if (!/^[a-f0-9-]{36}$/i.test(body.id ?? '') || !body.values || typeof body.values !== 'object' || typeof body.reason !== 'string') return Response.json({error:'Ogiltiga uppgifter'}, {status:400});
  const {data,error} = await db.rpc('kpi_approve_workify_order_review',{p_row_id:body.id,p_values:body.values,p_reason:body.reason});
  if(error) return Response.json({error:error.message}, {status:400});
  return Response.json(data);
 } catch {return Response.json({error:'Kunde inte godkänna raden'}, {status:400});}
}
