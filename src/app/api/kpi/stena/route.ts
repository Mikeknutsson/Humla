import {createHash} from 'node:crypto';
import {createClient} from '@/lib/supabase/server';
import {stenaWorkbook,normalizeStena} from '@/lib/hub/stena-import';
export const runtime='nodejs';export const maxDuration=120;
export async function POST(request:Request){
 if(request.headers.get('origin')!==new URL(request.url).origin)return Response.json({error:'Ogiltigt ursprung'},{status:403});
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return Response.json({error:'Logga in först'},{status:401});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').maybeSingle();
 if(!member)return Response.json({error:'Aktiv arbetsyta saknas'},{status:403});
 const {data:allowed}=await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.manage'});if(!allowed)return Response.json({error:'Importbehörighet saknas'},{status:403});
 try{
 const form=await request.formData(),file=form.get('file'),action=String(form.get('action')??'columns');
 if(!(file instanceof File)||! /\.xlsx?$/i.test(file.name)||file.size>3*1024*1024)throw Error('Välj en Excel-fil (.xls eller .xlsx), max 3 MB');
 if(!['columns','preview','import'].includes(action))throw Error('Ogiltig åtgärd');
 const bytes=new Uint8Array(await file.arrayBuffer()),table=stenaWorkbook(bytes,String(form.get('sheet')??''),Number(form.get('header')??1));
 if(action==='columns')return Response.json({headers:table.headers,sheet:table.sheet,sheets:table.sheets,totalRows:table.rows.length});
 const mapping=JSON.parse(String(form.get('mapping')??'{}'));if(!mapping||Array.isArray(mapping)||typeof mapping!=='object'||Object.values(mapping).some(v=>typeof v!=='string'))throw Error('Ogiltig kolumnmappning');
 const kind=String(form.get('kind')??''),rows=normalizeStena(table,mapping,kind),hash=createHash('sha256').update(bytes).digest('hex');
 const {data,error}=await db.rpc('hub_stena_upload_v1',{p_tenant:member.tenant_id,p_hash:hash,p_name:file.name,p_kind:kind,p_rows:rows,p_original:action==='import'?Buffer.from(bytes).toString('base64'):'',p_mapping:{columns:mapping,sheet:table.sheet,header:Number(form.get('header')??1)},p_commit:action==='import'}).abortSignal(AbortSignal.timeout(90000));
 if(error){console.error('[stena-import]',{code:error.code,message:error.message});throw Error('Stena-importen kunde inte slutföras. Ingen ofullständig fil publiceras. Kontrollera filen eller försök igen.');}
 return Response.json(data);
 }catch(e){return Response.json({error:e instanceof Error?e.message:'Filen kunde inte läsas'},{status:422});}
}
