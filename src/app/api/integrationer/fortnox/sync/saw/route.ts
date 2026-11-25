import {setTimeout} from 'node:timers/promises';
import {configuration,fortnoxRequest,owner,token} from '@/lib/fortnox/server';
import {fetchSawInvoices} from '@/lib/fortnox/saw-invoices';
import {saveSawControl} from '@/lib/fortnox/saw-control';
import {validTransportDate} from '@/lib/kpi/transport-leader';

export const runtime = 'nodejs';
export const maxDuration = 300;

export async function POST(request: Request) {
  const member = await owner();
  if (!member) return Response.json({error:'Ägarbehörighet krävs.'},{status:403});
  if (!configuration()) return Response.json({error:'Fortnox-integrationen saknar konfiguration.'},{status:503});
  const body = await request.json().catch(() => null);
  const {from,to} = body ?? {};
  if (typeof from !== 'string' || typeof to !== 'string' || !validTransportDate(from) || !validTransportDate(to)
    || from > to || Date.parse(to)-Date.parse(from) > 366*86400000) {
    return Response.json({error:'Välj ett giltigt datumintervall på högst ett verksamhetsår.'},{status:400});
  }

  try {
    const accessToken = await token(member.tenant_id);
    const started = Date.now();
    let nextRequest = started;
    const coverage = await fetchSawInvoices(async path => {
      if (Date.now()-started > 255000) throw Error('Synkningen tog för lång tid. Välj ett kortare datumintervall.');
      await setTimeout(Math.max(0,nextRequest-Date.now()));
      nextRequest = Date.now()+300;
      try {
        return await fortnoxRequest(accessToken,path,AbortSignal.timeout(15000));
      } catch (error) {
        if (!(error instanceof Error) || error.message !== 'Fortnox API 429') throw error;
        await setTimeout(5000);
        nextRequest = Date.now()+300;
        return fortnoxRequest(accessToken,path,AbortSignal.timeout(15000));
      }
    },from,to);
    await saveSawControl(member.tenant_id,coverage);
    return Response.json({rows:coverage.rows.length});
  } catch (error) {
    const message = error instanceof Error ? error.message : '';
    const known = /^(?:Fortnox returnerade|En Fortnoxfaktura|Fakturadatum|Kontrollen innehåller|En artikelrad|Synkningen tog|Underlaget gick)/.test(message);
    return Response.json({error:known ? message : message === 'Fortnox not connected'
      ? 'Anslut Fortnox innan du hämtar fakturarader.'
      : 'Fakturaraderna kunde inte hämtas. Kontrollera Fortnox-anslutningen och behörigheten för kundfakturor.'},{status:502});
  }
}
