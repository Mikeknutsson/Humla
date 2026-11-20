import {createHash} from 'node:crypto';
import {createClient} from '@/lib/supabase/server';
import {parseJohanssonWorkbook, type CheckedLoad, type Invoice} from '@/lib/hub/johansson-material';
import {isDeviation, deviationKey, reviewLabels, type MaterialReview} from '@/lib/hub/johansson-review';

export const runtime = 'nodejs';
export const maxDuration = 45;
const maxBytes = 4 * 1024 * 1024;
const excel = /\.xlsx?$/i;

async function materialAccess(request: Request) {
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
  return {db, tenant: member.tenant_id};
}

async function saveCheck(
  {db, tenant}: Exclude<Awaited<ReturnType<typeof materialAccess>>, Response>,
  key: string,
  {name, source, skipped, invoices}: Pick<MaterialReview, 'name' | 'source' | 'skipped'> & {invoices: Invoice[]},
) {
  const loads = invoices.flatMap(invoice => invoice.loads);
  const {data, error} = await db.rpc('hub_johansson_material_control', {p_tenant: tenant, p_loads: loads});
  if (error) {
    console.error('Material control query failed', error.code);
    return Response.json({error: 'Matchning mot Workify och prislistor misslyckades. Försök igen.'}, {status: 502});
  }
  type Check = Pick<CheckedLoad, 'sheet' | 'row' | 'match' | 'workify_articles' | 'workify_rates' | 'workify_registrations' | 'rate' | 'amount' | 'price_source'>;
  const checks = new Map((data as Check[]).map(check => [JSON.stringify([check.sheet, check.row]), check]));
  const report = {name, source, skipped, billing_review: true, invoices: invoices.map(invoice => ({
    ...invoice, loads: invoice.loads.map((load): CheckedLoad => {
      const check = checks.get(JSON.stringify([load.sheet, load.row]));
      if (!check) throw Error('Workify-kontrollen saknar ett resultat för en vägsedel.');
      const registrations = check.workify_registrations ?? [];
      return {
        ...load, ...check, workify_registrations: registrations,
        excel_registration: load.registration,
        registration: registrations.length === 1 ? registrations[0] : load.registration,
      };
    }),
  }))};
  const deviations = Object.fromEntries(report.invoices.flatMap(invoice => [
    ...invoice.loads.filter(load => isDeviation(load, true)).map(load => [deviationKey(invoice.name, load.row), {...load, workify_rates: undefined}] as const),
    ...invoice.issues.map(issue => [deviationKey(invoice.name, issue), issue] as const),
  ]));
  const saved = await db.rpc('hub_johansson_review', {
    p_tenant: tenant, p_action: 'register', p_key: key, p_report: report, p_deviations: deviations,
  });
  if (saved.error) {
    console.error('Material review could not be saved', saved.error.code);
    return Response.json({error: 'Bilagans granskning kunde inte sparas.'}, {status: 502});
  }
  return Response.json(saved.data);
}

export async function PATCH(request: Request) {
  const access = await materialAccess(request);
  if (access instanceof Response) return access;
  let payload;
  try { payload = await request.json(); } catch {
    return Response.json({error: 'Ogiltig begäran.'}, {status: 400});
  }
  const {action, key, revision, item, state} = payload ?? {};
  if (!['get', 'review', 'approve', 'reopen'].includes(action) || typeof key !== 'string' ||
      (action !== 'get' && !Number.isSafeInteger(revision)) ||
      (action === 'review' && (typeof item !== 'string' || typeof state !== 'string' || !Object.hasOwn(reviewLabels, state)))) {
    return Response.json({error: 'Ogiltig granskningsåtgärd.'}, {status: 400});
  }
  const {data, error} = await access.db.rpc('hub_johansson_review', {
    p_tenant: access.tenant, p_action: action, p_key: key,
    p_revision: action === 'get' ? null : revision,
    p_item: action === 'review' ? item : null, p_state: action === 'review' ? state : null,
  });
  if (!error) {
    const saved = data as MaterialReview;
    if ((action === 'get' || action === 'reopen') && !saved.approved_at && !saved.billing_review) {
      const invoices = saved.invoices.map(invoice => ({...invoice, loads: invoice.loads.map(({
        sheet, row, ticket, quarry, date, excel_registration, order, article, fraction, kg,
      }) => ({sheet, row, ticket, quarry, date, registration: excel_registration, order, article, fraction, kg}))}));
      try {
        return await saveCheck(access, key, {...saved, invoices});
      } catch {
        return Response.json({error: 'Kunddebiteringen kunde inte kontrolleras. Försök öppna bilagan igen.'}, {status: 502});
      }
    }
    return Response.json(data);
  }
  if (error.code === '40001') return Response.json({error: 'Bilagan har ändrats. Öppna den igen för att se aktuell status.'}, {status: 409});
  if (error.code === '23514') return Response.json({error: 'Granska alla öppna avvikelser innan du godkänner bilagan.'}, {status: 409});
  if (error.code === '42501') return Response.json({error: 'Behörighet saknas.'}, {status: 403});
  if (error.code === 'P0002') return Response.json({error: 'Bilagan kunde inte hittas.'}, {status: 404});
  return Response.json({error: 'Granskningen kunde inte uppdateras.'}, {status: 422});
}

export async function POST(request: Request) {
  const access = await materialAccess(request);
  if (access instanceof Response) return access;
  const {db, tenant} = access;
  if (Number(request.headers.get('content-length')) > maxBytes + 8192) {
    return Response.json({error: 'Excel-filen får vara högst 4 MB.'}, {status: 413});
  }

  try {
    const form = await request.formData();
    const upload = form.get('file');
    const id = form.get('id');
    let name: string;
    let bytes: ArrayBuffer;
    let key: string;
    let source: {subject: string | null; received_at: string | null} | null = null;
    if (upload instanceof File) {
      if (!excel.test(upload.name) || upload.size > maxBytes) throw Error('Välj en Excel-fil på högst 4 MB.');
      name = upload.name;
      bytes = await upload.arrayBuffer();
      key = `file:${createHash('sha256').update(new Uint8Array(bytes)).digest('hex')}`;
    } else {
      if (typeof id !== 'string' || !/^[a-f0-9-]{36}$/i.test(id)) throw Error('Välj en Excelbilaga.');
      key = `mail:${id.toLowerCase()}`;
      const {data: attachment} = await db.from('hub_gmail_attachments').select('filename,subject,received_at')
        .eq('id', id).eq('tenant_id', tenant).eq('status', 'stored').maybeSingle();
      if (!attachment || !excel.test(attachment.filename)) throw Error('Excelbilagan kunde inte hittas.');
      name = attachment.filename;
      source = {subject: attachment.subject, received_at: attachment.received_at};
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
    return await saveCheck(access, key, {name, source, skipped, invoices});
  } catch (error) {
    return Response.json({error: error instanceof Error ? error.message : 'Excel-filen kunde inte läsas.'}, {status: 422});
  }
}
