import {createClient} from '@/lib/supabase/server';
import {parseJohanssonWorkbook, type CheckedLoad} from '@/lib/hub/johansson-material';

export const runtime = 'nodejs';
export const maxDuration = 45;
const maxBytes = 4 * 1024 * 1024;
const excel = /\.xlsx?$/i;

export async function POST(request: Request) {
  if (request.headers.get('origin') !== new URL(request.url).origin) {
    return Response.json({error: 'Ogiltigt ursprung.'}, {status: 403});
  }
  const db = await createClient();
  const {data: {user}} = await db.auth.getUser();
  if (!user) return Response.json({error: 'Logga in igen.'}, {status: 401});
  const {data: member} = await db.from('hub_tenant_members').select('tenant_id')
    .eq('user_id', user.id).eq('status', 'active').maybeSingle();
  const {data: allowed} = member ? await db.rpc('hub_has_permission', {
    p_tenant_id: member.tenant_id, p_permission: 'kpi.manage',
  }) : {data: false};
  if (!member || !allowed) return Response.json({error: 'Behörighet saknas.'}, {status: 403});
  if (Number(request.headers.get('content-length')) > maxBytes + 8192) {
    return Response.json({error: 'Excel-filen får vara högst 4 MB.'}, {status: 413});
  }

  try {
    const form = await request.formData();
    const upload = form.get('file');
    const id = form.get('id');
    let name: string;
    let bytes: ArrayBuffer;
    if (upload instanceof File) {
      if (!excel.test(upload.name) || upload.size > maxBytes) throw Error('Välj en Excel-fil på högst 4 MB.');
      name = upload.name;
      bytes = await upload.arrayBuffer();
    } else {
      if (typeof id !== 'string' || !/^[a-f0-9-]{36}$/i.test(id)) throw Error('Välj en Excelbilaga.');
      const {data: attachment} = await db.from('hub_gmail_attachments').select('filename')
        .eq('id', id).eq('tenant_id', member.tenant_id).eq('status', 'stored').maybeSingle();
      if (!attachment || !excel.test(attachment.filename)) throw Error('Excelbilagan kunde inte hittas.');
      name = attachment.filename;
      const signed = await db.functions.invoke('gmail-document-import', {body: {action: 'download', id}});
      if (signed.error || !signed.data?.url) throw Error('Excelbilagan gick inte att öppna.');
      const url = new URL(signed.data.url);
      if (url.origin !== new URL(process.env.NEXT_PUBLIC_SUPABASE_URL!).origin ||
          !url.pathname.startsWith('/storage/v1/object/sign/')) throw Error('Ogiltig dokumentlänk.');
      const response = await fetch(url, {redirect: 'error', signal: AbortSignal.timeout(12000)});
      if (!response.ok || Number(response.headers.get('content-length')) > maxBytes) throw Error('Excelbilagan kunde inte hämtas eller är för stor.');
      bytes = await response.arrayBuffer();
      if (bytes.byteLength > maxBytes) throw Error('Excelbilagan är för stor.');
    }
    const {invoices, skipped} = parseJohanssonWorkbook(new Uint8Array(bytes));
    const loads = invoices.flatMap(invoice => invoice.loads);
    const {data, error} = await db.rpc('hub_johansson_material_control', {p_tenant: member.tenant_id, p_loads: loads});
    if (error) {
      console.error('Material control query failed', error.code);
      return Response.json({error: 'Matchning mot Workify och prislistor misslyckades. Försök igen.'}, {status: 502});
    }
    const checks = new Map((data as CheckedLoad[]).map(check => [JSON.stringify([check.sheet, check.row]), check]));
    return Response.json({name, skipped, invoices: invoices.map(invoice => ({
      ...invoice, loads: invoice.loads.map(load => ({...load, ...checks.get(JSON.stringify([load.sheet, load.row]))})),
    }))});
  } catch (error) {
    return Response.json({error: error instanceof Error ? error.message : 'Excel-filen kunde inte läsas.'}, {status: 422});
  }
}
