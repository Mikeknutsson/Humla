'use client';

import {useEffect, useRef, useState, type FormEvent} from 'react';
import type {CheckedLoad} from '@/lib/hub/johansson-material';
import {deviationKey, hasWorkifyCharge, isDeviation, reviewLabels, type DocumentEntry, type MaterialReview, type ReviewState} from '@/lib/hub/johansson-review';
import styles from './workspace.module.css';

type Attachment = {id: string; filename: string; subject: string; received_at: string; likely: boolean};
type CheckedInvoice = MaterialReview['invoices'][number];
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

const registrationLabel = (registration: string) => registration === 'LASTBIL' ? 'Inhyrd lastbil' : registration;

function RegistrationEvidence({load}: {load: CheckedLoad}) {
  const registrations = load.workify_registrations;
  if (registrations.length === 1) {
    return load.excel_registration !== load.registration &&
      <div>Regnummer från Workify <strong>{registrationLabel(load.registration)}</strong> · Excel <strong>{load.excel_registration || 'saknas'}</strong></div>;
  }
  if (registrations.length > 1) return <div className={styles.warning}>
    Flera regnummer i Workify ({registrations.map(registrationLabel).join(', ')}). Excel: {load.excel_registration || 'saknas'}.
  </div>;
  if (load.match === 'matched' || load.match === 'equivalent' || load.match === 'article_missing') {
    return <div className={styles.warning}>Regnummer saknas på Workify-ordern. Excel: {load.excel_registration || 'saknas'}.</div>;
  }
  return null;
}

function totals(loads: CheckedLoad[]) {
  return loads.reduce((sum, load) => ({
    kg: sum.kg + load.kg,
    cents: sum.cents + Math.round((load.amount ?? 0) * 100),
    priced: sum.priced + Number(load.amount !== null),
  }), {kg: 0, cents: 0, priced: 0});
}

function Total({loads}: {loads: CheckedLoad[]}) {
  const sum = totals(loads);
  const unpriced = loads.length - sum.priced;
  return <span className={styles.total}>
    <span>{tonnes.format(sum.kg / 1000)} ton</span>
    <strong>{sum.priced ? money.format(sum.cents / 100) : '–'}</strong>
    {unpriced > 0 && <span className={styles.warning}>{unpriced} utan inköpspris</span>}
  </span>;
}

type ReviewControls = {
  statuses: MaterialReview['statuses'];
  editable: boolean;
  billingReview?: true;
  busy: boolean;
  onReview: (item: string, state: ReviewState) => void;
};

function StatusField({item, controls}: {item: string; controls: ReviewControls}) {
  const state = controls.statuses[item]?.state ?? 'todo';
  if (!controls.editable) return <span>{reviewLabels[state]}</span>;
  return <div className={styles.statusField}>
    {state !== 'reviewed' && <button type="button" className="secondary" disabled={controls.busy}
      onClick={() => controls.onReview(item, 'reviewed')}>Markera granskad</button>}
    <label>
      <span className={styles.srOnly}>Granskningsstatus</span>
      <select value={state} disabled={controls.busy} onChange={event => controls.onReview(item, event.target.value as ReviewState)}>
        {Object.entries(reviewLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
      </select>
    </label>
  </div>;
}

function openItems(invoice: CheckedInvoice, statuses: MaterialReview['statuses'], billingReview?: true) {
  return [
    ...invoice.loads.filter(load => isDeviation(load, billingReview)).map(load => deviationKey(invoice.name, load.row)),
    ...invoice.issues.map(issue => deviationKey(invoice.name, issue)),
  ].filter(item => statuses[item]?.state !== 'reviewed').length;
}

function IssueCard({invoice, issue, controls}: {invoice: string; issue: string; controls: ReviewControls}) {
  return <article className={styles.load}>
    <strong>Kontrollera Excel · {invoice}</strong>
    <div>{issue}</div>
    <StatusField item={deviationKey(invoice, issue)} controls={controls}/>
  </article>;
}

function InvoicePanel({invoice, controls}: {
  invoice: CheckedInvoice; controls: ReviewControls;
}) {
  const vehicles = new Map<string, CheckedLoad[]>();
  for (const load of invoice.loads) {
    const registration = load.registration || 'Regnummer saknas';
    const rows = vehicles.get(registration) ?? [];
    rows.push(load);
    vehicles.set(registration, rows);
  }
  const sortedVehicles = [...vehicles].sort(([a], [b]) => a.localeCompare(b, 'sv'));
  const remaining = openItems(invoice, controls.statuses, controls.billingReview);
  return <section className={`panel ${styles.card}`}>
    <div className={styles.heading}><h2>{invoice.name}</h2><Total loads={invoice.loads}/></div>
    <p>{invoice.loads.length} vägsedlar · {vehicles.size} fordonsgrupper · {remaining} att granska</p>
    {invoice.issues.length > 0 && <details className={styles.vehicle}>
      <summary>{invoice.issues.length} rader att kontrollera i Excel</summary>
      {invoice.issues.map(issue => <IssueCard key={issue} invoice={invoice.name} issue={issue} controls={controls}/>)}
    </details>}
    {sortedVehicles.map(([registration, loads]) => {
      const flagged = loads.filter(load => isDeviation(load, controls.billingReview));
      const pending = flagged.filter(load => controls.statuses[deviationKey(invoice.name, load.row)]?.state !== 'reviewed').length;
      return <details key={registration} className={styles.vehicle}>
        <summary>
          <strong>{registrationLabel(registration)}</strong>
          <Total loads={loads}/>
          {pending > 0 && <span className={styles.warning}>{pending} att granska</span>}
        </summary>
        <div className={styles.loads}>
          {loads.map(load => <LoadCard key={load.row} invoice={invoice.name} load={load} controls={controls}/>)}
        </div>
      </details>;
    })}
  </section>;
}

function LoadCard({load, invoice, controls}: {load: CheckedLoad; invoice: string; controls: ReviewControls}) {
  const item = deviationKey(invoice, load.row);
  const unresolved = isDeviation(load, controls.billingReview);
  const batch = load.workify_combined;
  const reason = batch && batch.kg !== batch.workify_kg
    ? `Viktskillnad på samlingsraden: ${tonnes.format(Math.abs(batch.kg - batch.workify_kg) / 1000)} ton`
    : load.match === 'matched' || load.match === 'equivalent' ? 'Kunddebitering ej verifierad' : labels[load.match];
  return <article className={styles.load}>
    <div className={styles.heading}><strong>{load.article}</strong><span>{tonnes.format(load.kg / 1000)} ton</span></div>
    <div className={styles.context}>Order {load.order || '–'} · {registrationLabel(load.registration) || 'Regnummer saknas'} · <time>{load.date}</time></div>
    {unresolved && <div className={styles.reason}>{reason}</div>}
    {unresolved && <StatusField item={item} controls={controls}/>}
    <details className={styles.evidence}>
      <summary>Visa underlag</summary>
      <div className={styles.evidenceBody}>
        <div>Flik {invoice} · Vägsedel {load.ticket} · Excelrad {load.row}</div>
        <RegistrationEvidence load={load}/>
        <div className={styles.badges}>
          <span data-status={load.match}>{labels[load.match]}</span>
          {controls.billingReview && <span data-status={hasWorkifyCharge(load) ? 'matched' : 'article_missing'}>
            {hasWorkifyCharge(load) ? (load.workify_combined ? 'Matchad mot samlingsrad i Workify' : 'Debiterad i Workify') : 'Kunddebitering ej verifierad'}
          </span>}
          {load.amount === null && <span data-status="unpriced">Inköpspris saknas</span>}
        </div>
        {load.workify_articles.length > 0 && <div>Workify · {load.workify_articles.join(', ')}</div>}
        {load.workify_period && <div>
          <strong>Ordertotal matchar över flera dagar</strong>
          <div>{load.workify_period.load_count} vägsedlar · Johanssons {tonnes.format(load.workify_period.kg / 1000)} ton · Workify {tonnes.format(load.workify_period.workify_kg / 1000)} ton på {load.workify_period.workify_lines} rader</div>
          <ul>{load.workify_period.days.map(day => <li key={day.date}>
            {day.date} · Johanssons {tonnes.format(day.supplier_kg / 1000)} ton · Workify {tonnes.format(day.workify_kg / 1000)} ton
          </li>)}</ul>
        </div>}
        {load.workify_combined && <div>
          Samlingsrad{load.workify_combined.date && ` ${load.workify_combined.date}`} · {load.workify_combined.load_count} vägsedlar · Johanssons {tonnes.format(load.workify_combined.kg / 1000)} ton · Workify {tonnes.format(load.workify_combined.workify_kg / 1000)} ton
        </div>}
        {!!load.workify_receipts?.length && <div>
          Avläst kvitto på Workify-ordern · {load.workify_receipts.map(receipt =>
            [receipt.date, receipt.reference].filter(Boolean).join(' · ')).filter(Boolean).join(', ')}
        </div>}
        {load.workify_article_date && load.workify_article_date !== load.date &&
          <div>Artikeldatum i Workify · {load.workify_article_date}</div>}
        {!!load.workify_rates?.length && <div>Orderpris i Workify · {load.workify_rates.map(rate => `${money.format(rate)}/ton`).join(', ')}</div>}
        <div>Inköp · {tonnes.format(load.kg / 1000)} ton{load.rate !== null && ` × ${money.format(load.rate)}/ton`}
          {load.amount !== null && <strong> = {money.format(load.amount)}</strong>}</div>
        {load.price_source && <small>{load.price_source}</small>}
      </div>
    </details>
  </article>;
}

type QueueItem = {key: string; invoice: string} & ({load: CheckedLoad; issue?: never} | {load?: never; issue: string});
type ReviewView = 'open' | 'reviewed' | 'all';

function reviewQueue(report: MaterialReview): QueueItem[] {
  return report.invoices.flatMap(invoice => [
    ...invoice.loads.filter(load => isDeviation(load, report.billing_review)).map(load =>
      ({key: deviationKey(invoice.name, load.row), invoice: invoice.name, load})),
    ...invoice.issues.map(issue => ({key: deviationKey(invoice.name, issue), invoice: invoice.name, issue})),
  ]);
}

export default function MaterialWorkspace({attachments, mailAvailable, mailError, saved, listError}: {
  attachments: Attachment[]; mailAvailable: boolean; mailError: boolean; saved: DocumentEntry[]; listError: boolean;
}) {
  const [report, setReport] = useState<MaterialReview | null>(null);
  const [documents, setDocuments] = useState(saved);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [view, setView] = useState<ReviewView>('open');
  const [search, setSearch] = useState('');
  const resultsHeading = useRef<HTMLHeadingElement>(null);
  const reportKey = report?.key;
  useEffect(() => {
    if (reportKey) resultsHeading.current?.focus();
  }, [reportKey]);
  const archive = documents.filter(document => document.approved_at);
  const active = documents.filter(document => !document.approved_at);
  const archivedKeys = new Set(archive.map(document => document.key));
  const available = attachments.filter(file => !archivedKeys.has(`mail:${file.id}`));
  const queue = report ? reviewQueue(report) : [];
  const reviewed = queue.filter(item => report?.statuses[item.key]?.state === 'reviewed').length;
  const remaining = queue.length - reviewed;
  const term = search.trim().toLocaleLowerCase('sv');
  const visibleQueue = queue.filter(item =>
    (report?.statuses[item.key]?.state === 'reviewed') === (view === 'reviewed') &&
    [item.invoice, item.issue, item.load?.order, item.load?.ticket, item.load?.article, item.load?.registration,
      item.load && registrationLabel(item.load.registration), item.load?.excel_registration]
      .some(value => value?.toLocaleLowerCase('sv').includes(term)));
  const controls: ReviewControls | undefined = report && {
    statuses: report.statuses, billingReview: report.billing_review, editable: !report.approved_at, busy,
    onReview: (item, state) => change('review', report.key, item, state),
  } || undefined;

  function show(result: MaterialReview) {
    if (report?.key !== result.key) {
      setView(result.approved_at ? 'all' : 'open');
      setSearch('');
    }
    setReport(result);
    const {key, name, source, updated_at, approved_at} = result;
    setDocuments(previous => [{key, name, source, updated_at, approved_at}, ...previous.filter(document => document.key !== key)]);
  }

  async function change(action: 'get' | 'review' | 'approve' | 'reopen', key: string, item?: string, state?: ReviewState) {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const response = await fetch('/api/kpi/johansson-material', {
        method: 'PATCH', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({action, key, revision: report?.revision, item, state}),
      });
      const payload = await response.json();
      if (!response.ok) throw Error(payload.error ?? 'Granskningen kunde inte uppdateras.');
      show(payload);
      if (action === 'approve') {
        setReport(null);
        setNotice('Bilagan är godkänd och finns i arkivet.');
      }
      if (action === 'reopen') {
        setView('open');
        setNotice('Bilagan finns nu bland påbörjade granskningar.');
      }
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Granskningen kunde inte uppdateras.');
    } finally { setBusy(false); }
  }

  function documentList(items: DocumentEntry[]) {
    return <ul className={styles.documents}>{items.map(item => <li key={item.key}>
      <button type="button" className="secondary" disabled={busy} onClick={() => change('get', item.key)}>
        Öppna {item.name} · {day.format(new Date(item.source?.received_at ?? item.updated_at))}
        {item.source?.subject && ` · ${item.source.subject}`}
      </button>
    </li>)}</ul>;
  }
  async function check(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const input = new FormData(event.currentTarget);
    if (!input.get('id') && !(input.get('file') as File | null)?.size) return;
    setBusy(true);
    setError('');
    setNotice('');
    setReport(null);
    try {
      const response = await fetch('/api/kpi/johansson-material', {method: 'POST', body: input});
      const payload = await response.json();
      if (!response.ok) throw Error(payload.error ?? 'Kontrollen kunde inte köras.');
      show(payload);
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Kontrollen kunde inte köras.');
    } finally { setBusy(false); }
  }

  return <div className={`content ${styles.workspace}`}>
    <section className={`panel ${styles.card}`}>
      <h2 className={styles.intro}>Bilagor</h2>
      {active.length > 0 && <details className={styles.upload} open={!report ? true : undefined}>
        <summary>Påbörjade granskningar ({active.length})</summary>
        {documentList(active)}
      </details>}
      {mailAvailable && <form onSubmit={check} className={styles.form}>
        <label>Excelbilaga från mejl
          <select name="id" required defaultValue="" disabled={busy || available.length === 0}>
            <option value="">Välj bilaga</option>
            {available.map(file => <option key={file.id} value={file.id}>
              {day.format(new Date(file.received_at))} · {file.filename} · {file.subject || 'Utan ämne'}
            </option>)}
          </select>
        </label>
        <button className="secondary" disabled={busy || available.length === 0}>Kontrollera bilaga</button>
      </form>}
      {mailAvailable && !available.length && <p>{mailError ? 'Mejlbilagorna kunde inte hämtas.' : 'Det finns inga Excelbilagor att kontrollera.'}</p>}
      <details className={styles.upload} open={!mailAvailable ? true : undefined}>
        <summary>Välj Excel-fil från datorn</summary>
        <form onSubmit={check} className={styles.form}>
          <label>Johanssons materialunderlag<input type="file" name="file" accept=".xls,.xlsx" required disabled={busy}/></label>
          <button className="secondary" disabled={busy}>Kontrollera fil</button>
        </form>
      </details>
      <details className={styles.upload}>
        <summary>Arkiv ({archive.length})</summary>
        {archive.length ? documentList(archive) : <p>Inga godkända bilagor.</p>}
      </details>
      {listError && <p role="alert" className={styles.warning}>Sparade granskningar och arkivet kunde inte hämtas.</p>}
      {busy && <p role="status">Bearbetar bilagan…</p>}
      {notice && <p role="status">{notice}</p>}
      {error && !report && <p role="alert" className={styles.warning}>{error}</p>}
    </section>
    {report && controls && <>
      <section className={`panel ${styles.card}`}>
        <div className={styles.heading}>
          <h2 ref={resultsHeading} tabIndex={-1}>{report.name}</h2>
          <span>{report.invoices.reduce((sum, invoice) => sum + invoice.loads.length, 0)} vägsedlar · {report.invoices.length} fakturaflikar</span>
        </div>
        {error && <p role="alert" className={styles.warning}>{error}</p>}
        {report.approved_at ? <div className={styles.actions}>
          <span>Godkänd {day.format(new Date(report.approved_at))}</span>
          <button type="button" className="secondary" disabled={busy} onClick={() => change('reopen', report.key)}>Återöppna bilagan</button>
        </div> : <div className={styles.actions}>
          <button type="button" className="secondary" disabled={busy || remaining > 0} onClick={() => change('approve', report.key)}>Godkänn bilagan</button>
          <span>{remaining > 0 ? `Kvar att granska: ${remaining}` : 'Alla avvikelser är genomgångna.'}</span>
          <button type="button" className="secondary" disabled={busy} onClick={() => change('get', report.key)}>Hämta sparad status</button>
        </div>}
        <div className={styles.views} role="group" aria-label="Visa granskning">
          <button type="button" className="secondary" aria-pressed={view === 'open'} onClick={() => setView('open')}>Att granska ({remaining})</button>
          <button type="button" className="secondary" aria-pressed={view === 'reviewed'} onClick={() => setView('reviewed')}>Granskade ({reviewed})</button>
          <button type="button" className="secondary" aria-pressed={view === 'all'} onClick={() => setView('all')}>Alla vägsedlar och inköp</button>
        </div>
        {view !== 'all' && <label className={styles.search}>
          <span className={styles.srOnly}>Sök bland avvikelser</span>
          <input type="search" placeholder="Sök order, vägsedel, regnummer eller material" value={search} onChange={event => setSearch(event.target.value)}/>
        </label>}
        {view === 'all' && report.skipped.length > 0 && <p>Flikar utan läsbara materialtransaktioner · {report.skipped.join(', ')}</p>}
      </section>
      {view === 'all' ? report.invoices.map(invoice => <InvoicePanel key={invoice.name} invoice={invoice} controls={controls}/>) :
        <section className={`panel ${styles.card} ${styles.queue}`} aria-label={view === 'open' ? 'Att granska' : 'Granskade avvikelser'}>
          {visibleQueue.length === 0 && <p>{term ? 'Ingen avvikelse matchar din sökning.' : view === 'open' ? 'Inga öppna avvikelser.' : 'Inga avvikelser har markerats som granskade.'}</p>}
          {visibleQueue.map(item => item.load ?
            <LoadCard key={item.key} load={item.load} invoice={item.invoice} controls={controls}/> :
            <IssueCard key={item.key} invoice={item.invoice} issue={item.issue} controls={controls}/>)}
        </section>}
    </>}
  </div>;
}
