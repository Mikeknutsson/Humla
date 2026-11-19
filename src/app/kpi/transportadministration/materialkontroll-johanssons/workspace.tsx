'use client';

import {useState, type FormEvent} from 'react';
import type {CheckedLoad, Invoice} from '@/lib/hub/johansson-material';
import styles from './workspace.module.css';

type Attachment = {id: string; filename: string; subject: string; received_at: string; likely: boolean};
type CheckedInvoice = Omit<Invoice, 'loads'> & {loads: CheckedLoad[]};
type Report = {name: string; skipped: string[]; invoices: CheckedInvoice[]};
const money = new Intl.NumberFormat('sv-SE', {style: 'currency', currency: 'SEK'});
const tonnes = new Intl.NumberFormat('sv-SE', {maximumFractionDigits: 3});
const day = new Intl.DateTimeFormat('sv-SE', {timeZone: 'Europe/Stockholm'});
const labels = {
  matched: 'Artikel finns i Workify',
  equivalent: 'Motsvarande artikel enligt prislistan',
  order_missing: 'Order saknas i Workify-underlaget',
  article_missing: 'Artikeln saknas på ordern',
  order_unspecified: 'Ordernummer saknas på vägsedeln',
};
const needsReview = (load: CheckedLoad) => !['matched', 'equivalent'].includes(load.match) || load.amount === null || !load.registration;

function totals(loads: CheckedLoad[]) {
  return loads.reduce((sum, load) => ({
    kg: sum.kg + load.kg,
    cents: sum.cents + Math.round((load.amount ?? 0) * 100),
    priced: sum.priced + Number(load.amount !== null),
    review: sum.review + Number(needsReview(load)),
  }), {kg: 0, cents: 0, priced: 0, review: 0});
}

function Total({loads}: {loads: CheckedLoad[]}) {
  const sum = totals(loads);
  const unpriced = loads.length - sum.priced;
  return <span className={styles.total}>
    <span>{tonnes.format(sum.kg / 1000)} ton</span>
    <strong>{sum.priced ? money.format(sum.cents / 100) : '–'}</strong>
    {unpriced > 0 && <span className={styles.warning}>{unpriced} utan pris</span>}
  </span>;
}

function InvoicePanel({invoice, reviewOnly}: {invoice: CheckedInvoice; reviewOnly: boolean}) {
  const vehicles = new Map<string, CheckedLoad[]>();
  for (const load of invoice.loads) {
    const registration = load.registration || 'Regnummer saknas';
    const rows = vehicles.get(registration) ?? [];
    rows.push(load);
    vehicles.set(registration, rows);
  }
  const sortedVehicles = [...vehicles].sort(([a], [b]) => a.localeCompare(b, 'sv'));
  const sum = totals(invoice.loads);
  return <section className={`panel ${styles.card}`}>
    <div className={styles.heading}><h2>{invoice.name}</h2><Total loads={invoice.loads}/></div>
    <p>{invoice.loads.length} vägsedlar · {vehicles.size} fordonsgrupper · {sum.review + invoice.issues.length} att granska</p>
    {invoice.issues.length > 0 && <details className={styles.vehicle}>
      <summary className={styles.warning}>{invoice.issues.length} rader behöver kontrolleras i Excel</summary>
      <ul>{invoice.issues.map(issue => <li key={issue}>{issue}</li>)}</ul>
    </details>}
    {sortedVehicles.map(([registration, loads]) => {
      const flagged = loads.filter(needsReview);
      if (reviewOnly && !flagged.length) return null;
      return <details key={registration} className={styles.vehicle}>
        <summary>
          <strong>{registration}</strong>
          <Total loads={loads}/>
          {flagged.length > 0 && <span className={styles.warning}>{flagged.length} att granska</span>}
        </summary>
        <div className={styles.loads}>
          {(reviewOnly ? flagged : loads).map(load => <article key={load.row} className={styles.load}>
            <div className={styles.heading}><strong>{load.article}</strong><time>{load.date}</time></div>
            <span>Order {load.order || '–'} · Vägsedel {load.ticket} · Excelrad {load.row}</span>
            <div className={styles.badges}>
              <span data-status={load.match}>{labels[load.match]}</span>
              {load.amount === null && <span data-status="unpriced">Pris saknas</span>}
            </div>
            {load.workify_articles.length > 0 && <div>Workify · {load.workify_articles.join(', ')}</div>}
            <div>{tonnes.format(load.kg / 1000)} ton{load.rate !== null && ` × ${money.format(load.rate)}/ton`}
              {load.amount !== null && <strong> = {money.format(load.amount)}</strong>}</div>
            {load.price_source && <small>{load.price_source}</small>}
          </article>)}
        </div>
      </details>;
    })}
    {reviewOnly && sum.review === 0 && invoice.issues.length === 0 && <p>Inga avvikelser att granska.</p>}
  </section>;
}

export default function MaterialWorkspace({attachments, mailAvailable, mailError}: {
  attachments: Attachment[]; mailAvailable: boolean; mailError: boolean;
}) {
  const [report, setReport] = useState<Report | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [reviewOnly, setReviewOnly] = useState(false);
  async function check(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const input = new FormData(event.currentTarget);
    if (!input.get('id') && !(input.get('file') as File | null)?.size) return;
    setBusy(true);
    setError('');
    setReport(null);
    try {
      const response = await fetch('/api/kpi/johansson-material', {method: 'POST', body: input});
      const payload = await response.json();
      if (!response.ok) throw Error(payload.error ?? 'Kontrollen kunde inte köras.');
      setReport(payload);
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Kontrollen kunde inte köras.');
    } finally { setBusy(false); }
  }

  return <div className={`content ${styles.workspace}`}>
    <section className={`panel ${styles.card}`}>
      <p className={styles.intro}>Kontrollera materialet mot Workify och beräkna inköpsbelopp exkl. moms per fordon och fakturaflik.</p>
      {mailAvailable && <form onSubmit={check} className={styles.form}>
        <label>Excelbilaga från mejl
          <select name="id" required defaultValue="" disabled={busy || attachments.length === 0}>
            <option value="">Välj bilaga</option>
            {attachments.map(file => <option key={file.id} value={file.id}>
              {day.format(new Date(file.received_at))} · {file.filename} · {file.subject || 'Utan ämne'}
            </option>)}
          </select>
        </label>
        <button className="secondary" disabled={busy || attachments.length === 0}>Kontrollera bilaga</button>
      </form>}
      {mailAvailable && !attachments.length && <p>{mailError ? 'Mejlbilagorna kunde inte hämtas.' : 'Det finns inga sparade Excelbilagor.'}</p>}
      <details className={styles.upload} open={!mailAvailable ? true : undefined}>
        <summary>Välj Excel-fil från datorn</summary>
        <form onSubmit={check} className={styles.form}>
          <label>Johanssons materialunderlag<input type="file" name="file" accept=".xls,.xlsx" required disabled={busy}/></label>
          <button className="secondary" disabled={busy}>Kontrollera fil</button>
        </form>
      </details>
      {busy && <p role="status">Kontrollerar materialet mot Workify och prislistorna…</p>}
      {error && <p role="alert" className={styles.warning}>{error}</p>}
    </section>
    {report && <>
      <section className={`panel ${styles.card}`}>
        <div className={styles.heading}><h2>{report.name}</h2>
          <label className={styles.reviewFilter}><input type="checkbox" checked={reviewOnly} onChange={event => setReviewOnly(event.target.checked)}/> Visa bara avvikelser</label>
        </div>
        <p>{report.invoices.length} fakturaflikar · Belopp exkl. moms enligt prislistan på leveransdagen.</p>
        {report.skipped.length > 0 && <p>Flikar utan läsbara materialtransaktioner · {report.skipped.join(', ')}</p>}
      </section>
      {report.invoices.map(invoice => <InvoicePanel key={invoice.name} invoice={invoice} reviewOnly={reviewOnly}/>)}
    </>}
  </div>;
}
