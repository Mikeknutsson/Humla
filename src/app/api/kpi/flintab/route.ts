import {createHash} from 'node:crypto';
import {flintabHeaders,parseFlintab} from '@/lib/hub/flintab';
import {yardAccess} from '@/lib/hub/sortergard-server';

export const maxDuration = 60;

export async function POST(request: Request) {
  const access = await yardAccess();
  if (!access) return Response.json({error:'Behörighet saknas.'},{status:403});
  try {
    const form = await request.formData();
    const file = form.get('file');
    if (!(file instanceof File) || !/\.xlsx?$/i.test(file.name) || file.size > 2097152) {
      return Response.json({error:'Välj en Excel-fil från Flintab på högst 2 MB.'},{status:400});
    }
    const bytes = Buffer.from(await file.arrayBuffer());
    const sha = createHash('sha256').update(bytes).digest('hex');
    const commit = form.get('commit') === sha;
    const parsed = parseFlintab(bytes);
    const {data,error} = await access.db.rpc('hub_flintab_import',{
      p_tenant:access.tenantId, p_commit:commit,
      p_file:commit ? {filename:file.name,sheet:parsed.sheet,base64:bytes.toString('base64'),errors:parsed.errors} : {},
      p_rows:parsed.rows.map(r=>[r.id,r.date,r.kg,r.direction,r.row,...flintabHeaders.map(key=>r.raw[key])]),
    });
    if (error) return Response.json({error:'Hubben kunde inte behandla filen. Kontrollera filen och försök igen.'},{status:422});
    return Response.json({sha,commit,...data,totals:parsed.totals,weights:parsed.weights,count:parsed.rows.length,errors:parsed.errors,
      sample:parsed.rows.slice(0,8).map(row=>({id:row.id,date:row.date,material:row.raw['Artikel (Id)'],tonnes:row.kg/1000}))});
  } catch (error) {
    return Response.json({error:error instanceof Error ? error.message : 'Excel-filen kunde inte läsas.'},{status:422});
  }
}

export async function GET(request: Request) {
  const access = await yardAccess();
  if (!access) return new Response('Behörighet saknas.',{status:403});
  const id = new URL(request.url).searchParams.get('id');
  if (!id || !/^[a-f0-9-]{36}$/i.test(id)) return new Response('Filen saknas.',{status:404});
  const {data,error} = await access.db.rpc('hub_flintab_history',{p_tenant:access.tenantId,p_id:id});
  if (error || !data?.base64) return new Response('Filen saknas.',{status:404});
  const extension = /\.xls$/i.test(data.filename) ? 'xls' : 'xlsx';
  return new Response(Uint8Array.from(Buffer.from(data.base64,'base64')),{headers:{
    'Content-Type':'application/octet-stream','Content-Disposition':`attachment; filename="flintab.${extension}"; filename*=UTF-8''${encodeURIComponent(data.filename).replace(/['()]/g,c=>'%'+c.charCodeAt(0).toString(16))}`,
    'Cache-Control':'private, no-store',
  }});
}
