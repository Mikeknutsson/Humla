import Link from 'next/link';
import {configuration} from '@/lib/fortnox/server';
import {readSawControl} from '@/lib/fortnox/saw-control';
import {sawArticles} from '@/lib/fortnox/saw-invoices';
import type {createClient} from '@/lib/supabase/server';
import FortnoxSawSync from './fortnox-saw-sync';

const currency = new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK'});
const money = (value: number | null) => value === null ? 'Underlag saknas' : currency.format(value);
const date = new Intl.DateTimeFormat('sv-SE',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Stockholm'});

export async function FortnoxSawControl({db,tenant,from,to,months}: {
  db: Awaited<ReturnType<typeof createClient>>; tenant: string; from: string; to: string; months: number[] | null;
}) {
  const configured = configuration();
  const [fortnox, workify] = await Promise.all([
    configured ? readSawControl(tenant,from,to) : {connected:false,snapshot:null},
    db.rpc('hub_workify_saw_control',{p_tenant:tenant,p_from:from,p_to:to,p_months:months}),
  ]);
  const workifyRows = (workify.data ?? []) as {article:string;workify_status:string;amount:number|null}[];
  const snapshot = fortnox.snapshot;
  const rows = snapshot?.rows.filter(row => row.date >= from && row.date <= to &&
    (!months || months.includes(Number(row.date.slice(5,7))))) ?? [];
  const totals = sawArticles.map(article => {
    const w = workifyRows.filter(row => row.article === article);
    const f = rows.filter(row => row.article === article);
    const invoices = snapshot ? f.reduce((total,row) => total+row.amount,0) : null;
    const workifyInvoiced = workify.error || !w.length ? null :
      w.filter(row => row.workify_status === 'Invoiced').reduce((total,row) => total+Number(row.amount),0);
    const other = workify.error || !w.length ? null :
      w.filter(row => row.workify_status !== 'Invoiced').reduce((total,row) => total+Number(row.amount),0);
    return {article,invoices,workifyInvoiced,other,delta:invoices === null || workifyInvoiced === null ? null : invoices-workifyInvoiced};
  });

  return <section className="panel">
    <h2>Fortnox-kontroll för sågning</h2>
    <p>Beloppen är exklusive moms och före fördelning till lastbil och sågning. Fortnox använder fakturadatum och Workify använder arbetsdatum.</p>
    {!configured ? <p role="status">Fortnox-anslutningen behöver konfigureras.</p> : !fortnox.connected
      ? <Link href="/api/integrationer/fortnox/connect" prefetch={false}>Anslut Fortnox</Link>
      : <FortnoxSawSync key={from+'_'+to} from={from} to={to}/>}
    {snapshot ? <p>Hämtat från Fortnox {date.format(new Date(snapshot.fetchedAt))}. Bokförda kundfakturor och krediter ingår.</p>
      : <p role="status">Fortnox-underlag saknas för den valda perioden.</p>}
    <div className="monthly-scroll"><table>
      <thead><tr><th>Artikel</th><th>Fortnox fakturerat netto</th><th>Workify markerat fakturerat</th><th>Övrigt Workify-underlag</th><th>Fortnox minus fakturerat i Workify</th></tr></thead>
      <tbody>{totals.map(row => <tr key={row.article}><th scope="row">{row.article}</th><td>{money(row.invoices)}</td>
        <td>{money(row.workifyInvoiced)}</td><td>{money(row.other)}</td><td>{money(row.delta)}</td></tr>)}</tbody>
    </table></div>
    {rows.length > 0 && <details><summary>Visa fakturarader från Fortnox ({rows.length})</summary>
      <div className="monthly-scroll"><table>
        <thead><tr><th>Fakturadatum</th><th>Fakturanummer</th><th>Kund</th><th>Orderreferens</th><th>Artikel</th><th>Belopp exkl. moms</th></tr></thead>
        <tbody>{rows.map((row,index) => <tr key={row.invoice+'-'+row.row+'-'+index}>
          <td>{row.date}</td><td>{row.invoice}{row.credit && ' · Kredit'}</td><td>{row.customer || '–'}</td>
          <td>{row.reference || '–'}</td><td>{row.article}</td><td>{money(row.amount)}</td>
        </tr>)}</tbody>
      </table></div>
    </details>}
  </section>;
}
