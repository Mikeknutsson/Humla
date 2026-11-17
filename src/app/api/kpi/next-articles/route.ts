import { createHash, randomUUID } from 'node:crypto';
import { createClient } from '@/lib/supabase/server';
import { nextArticleImportPreview, nextArticleImportSummary, readNextArticleFile } from '@/lib/kpi/next-article-file';

export const runtime='nodejs';

export async function POST(request:Request) {
  if(request.headers.get('origin')!==new URL(request.url).origin)return Response.json({error:'Ogiltigt ursprung.'},{status:403});
  const db=await createClient();
  const {data:{user}}=await db.auth.getUser();
  if(!user)return Response.json({error:'Logga in först.'},{status:401});
  const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').maybeSingle();
  if(!member)return Response.json({error:'Aktiv arbetsyta saknas.'},{status:403});
  const tenantId=member.tenant_id;
  const {data:allowed}=await db.rpc('hub_has_permission',{p_tenant_id:tenantId,p_permission:'kpi.manage'});
  if(!allowed)return Response.json({error:'Importbehörighet saknas.'},{status:403});

  const form=await request.formData().catch(()=>null);
  const file=form?.get('file'), mode=form?.get('mode');
  if(!(file instanceof File)||! /\.xlsx?$/i.test(file.name)||file.size>4_000_000||file.name.length>200)
    return Response.json({error:'Välj en Excel-fil (.xlsx eller .xls) på högst 4 MB.'},{status:400});
  if(mode!=='preview'&&mode!=='import')return Response.json({error:'Ogiltig importåtgärd.'},{status:400});
  const bytes=new Uint8Array(await file.arrayBuffer());
  let parsed:ReturnType<typeof readNextArticleFile>;
  try {
    parsed=readNextArticleFile(bytes);
  } catch(error) {
    return Response.json({error:error instanceof Error?error.message:'Excel-filen kunde inte läsas.'},{status:422});
  }
  if(mode==='preview')return Response.json(nextArticleImportPreview(parsed));
  const {articles,sourceRows,periodStart,periodEnd}=parsed;

  const hash=createHash('sha256').update(bytes).digest('hex'), batchId=randomUUID();
  const path=`${tenantId}/${batchId}/${file.name.replace(/[^a-zA-Z0-9._-]/g,'_').slice(-120)}`;
  const bucket=db.storage.from('kpi-imports');
  const {error:uploadError}=await bucket.upload(path,bytes,{contentType:file.name.toLowerCase().endsWith('.xlsx')?
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':'application/vnd.ms-excel',upsert:false});
  if(uploadError)return Response.json({error:'Originalfilen kunde inte sparas.'},{status:500});
  const {data,error}=await db.rpc('hub_next_article_upload',{
    t:tenantId,p_id:batchId,p_file:file.name,p_hash:hash,p_path:path,p_rows:articles,
    p_source_rows:sourceRows,p_from:periodStart,p_to:periodEnd,
  });
  if(data?.duplicate||error?.code==='22023'||error?.code==='42501')await bucket.remove([path]);
  if(error||!data){
    console.error('[next-article-import]',{code:error?.code});
    return Response.json({error:'NeXT-artiklarna kunde inte sparas. Kontrollera Importhistorik innan du försöker igen.'},{status:422});
  }
  return Response.json({...nextArticleImportSummary(parsed),...data});
}
