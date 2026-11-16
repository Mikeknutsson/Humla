import { createHash, randomUUID } from 'node:crypto';
import { createClient } from '@/lib/supabase/server';
import { readNextProjectFile } from '@/lib/kpi/next-project-file';

export const runtime='nodejs';

export async function POST(request:Request){
  if(request.headers.get('origin')!==new URL(request.url).origin)return Response.json({error:'Ogiltigt ursprung.'},{status:403});
  const db=await createClient();
  const {data:{user}}=await db.auth.getUser();
  if(!user)return Response.json({error:'Logga in först.'},{status:401});
  const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
  if(!member)return Response.json({error:'Aktiv arbetsyta saknas.'},{status:403});
  const tenantId=member.tenant_id;
  const {data:allowed}=await db.rpc('hub_has_permission',{p_tenant_id:tenantId,p_permission:'kpi.manage'});
  if(!allowed)return Response.json({error:'Importbehörighet saknas.'},{status:403});

  try{
    const form=await request.formData();
    const file=form.get('file');
    const mode=form.get('mode');
    if(!(file instanceof File)||! /\.xlsx?$/i.test(file.name)||file.size>4_000_000||file.name.length>200)
      return Response.json({error:'Välj en Excel-fil (.xlsx eller .xls) på högst 4 MB.'},{status:400});
    if(mode!=='preview'&&mode!=='import')return Response.json({error:'Ogiltig importåtgärd.'},{status:400});
    const bytes=new Uint8Array(await file.arrayBuffer());
    const {projects,invalidCostCenterRows}=readNextProjectFile(bytes);
    const warnings={
      count:invalidCostCenterRows.length,
      rows:invalidCostCenterRows.slice(0,10),
    };
    if(mode==='preview')return Response.json({rows:projects.length,preview:projects.slice(0,5),warnings});
    const hash=createHash('sha256').update(bytes).digest('hex');
    const batchId=randomUUID();
    const path=`${tenantId}/${batchId}/${file.name.replace(/[^a-zA-Z0-9._-]/g,'_').slice(-120)}`;
    const bucket=db.storage.from('kpi-imports');
    const upload=await bucket.upload(path,bytes,{contentType:file.name.toLowerCase().endsWith('.xlsx')?
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':'application/vnd.ms-excel',upsert:false});
    if(upload.error)return Response.json({error:'Originalfilen kunde inte sparas.'},{status:500});
    const {data,error}=await db.rpc('hub_next_project_upload',{t:tenantId,p_id:batchId,p_file:file.name,p_hash:hash,p_path:path,p_rows:projects});
    if(data?.duplicate)await bucket.remove([path]);
    if(error){
      console.error('[next-project-import]',{code:error.code});
      return Response.json({error:'Projektimporten kunde inte slutföras. Kontrollera Importhistorik innan du försöker igen.'},{status:422});
    }
    return Response.json({...data,warnings});
  }catch(error){
    return Response.json({error:error instanceof Error?error.message:'Projektfilen kunde inte läsas.'},{status:422});
  }
}
