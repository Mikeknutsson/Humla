'use client';

import {useState} from 'react';

const billingLabels = {
  billed: 'Fakturerad i Workify',
  unbilled: 'Ej fakturerad i Workify',
  partial: 'Faktureringsmarkering på vissa rader',
  unknown: 'Faktureringsstatus saknas',
  missing_order: 'Workify-order saknas',
};
const comparisonLabels = {
  comparable: 'Mängder jämförda',
  missing_reference: 'Orderreferens saknas',
  missing_order: 'Saknas i Workify-importen',
  no_ton_lines: 'Ordern saknar tonrader',
  material_mismatch: 'Material och Workify-artikel behöver matchas',
  multiple_or_incomplete: 'Mängder behöver kontrolleras manuellt',
};

type Ticket = {
  id: string;
  day: string;
  ticket_number: string | null;
  source_record_id: string;
  vehicle_registration: string | null;
  material_name: string | null;
  tonnes: number;
};

type OrderLine = {
  file_name: string;
  row_number: number;
  day: string | null;
  article: string | null;
  unit: string | null;
  quantity: number | null;
  price: number | null;
  amount: number | null;
  currency: string | null;
  billed: boolean | null;
};

export type Delivery = {
  order_number: string | null;
  first_day: string;
  last_day: string;
  weighed_tonnes: number;
  load_count: number;
  vehicles: string | null;
  materials: string | null;
  customers: string | null;
  comparison_status: keyof typeof comparisonLabels;
  billing_status: keyof typeof billingLabels;
  order_tonnes: number | null;
  difference_tonnes: number | null;
  indicative_sek: number | null;
  tickets: Ticket[];
  workify_lines: OrderLine[] | null;
};

const tonnes = new Intl.NumberFormat('sv-SE', {maximumFractionDigits: 3});
const money = new Intl.NumberFormat('sv-SE', {maximumFractionDigits: 2});
const format = (value: number | null, formatter = tonnes) => value == null ? '—' : formatter.format(value);

function OrderNumber({value}: {value: string}) {
  const [copied, setCopied] = useState(false);
  return <button type="button" className="btn" aria-label={`Kopiera ordernummer ${value}`} onClick={async () => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  }}><strong>{value}</strong>{copied && <span role="status"> · Kopierat</span>}</button>;
}

function Evidence({row}: {row: Delivery}) {
  return <details>
    <summary>{row.load_count} lass · {row.workify_lines?.length ?? 0} orderrader</summary>
    <p><strong>Vågposter</strong></p>
    <ul>
      {row.tickets.map(ticket => <li key={ticket.id}>
        {ticket.day} · Vågpost {ticket.ticket_number || ticket.source_record_id} · {ticket.vehicle_registration || 'Reg.nr saknas'}
        {' · '}{ticket.material_name || 'Material saknas'} · {format(ticket.tonnes)} ton
      </li>)}
    </ul>
    {!!row.workify_lines?.length && <>
      <p><strong>Workify-rader</strong></p>
      <ul>
        {row.workify_lines.map((line, index) => <li key={`${line.file_name}-${line.row_number}-${index}`}>
          {line.article || 'Artikel saknas'} · {format(line.quantity)} {line.unit}
          {line.price != null && <> à {format(line.price, money)} {line.currency}</>}
          {line.amount != null && <> · {format(line.amount, money)} {line.currency}</>}
          {line.billed === true && ' · Fakturerad'}
          {line.billed === false && ' · Ej fakturerad'}
          <br/>{line.day || 'Datum saknas'} · {line.file_name}, rad {line.row_number}
        </li>)}
      </ul>
    </>}
  </details>;
}

function needsReview(row: Delivery) {
  return row.comparison_status !== 'comparable' || row.difference_tonnes !== 0 || row.billing_status !== 'billed';
}

export default function DeliveryWorkspace({rows}: {rows: Delivery[]}) {
  const [filter, setFilter] = useState('all');
  const [search, setSearch] = useState('');
  const term = search.trim().toLocaleLowerCase('sv-SE');
  const visible = rows.filter(row => {
    if (filter === 'review' && !needsReview(row)) return false;
    if (filter === 'matched' && !row.workify_lines) return false;
    if (filter === 'unmatched' && row.workify_lines) return false;
    return [row.order_number, row.customers, row.vehicles, row.materials].some(value =>
      value?.toLocaleLowerCase('sv-SE').includes(term)) || !term;
  });
  const loadCount = rows.reduce((sum, row) => sum + row.load_count, 0);
  const matched = rows.filter(row => row.workify_lines).length;

  return <section className="panel">
    <h2>Utvägda lass sedan 1 september 2026</h2>
    <p>{loadCount} lass · {matched} matchade Workify-ordrar · {rows.filter(needsReview).length} poster att granska</p>
    <p>Vägningar med samma orderreferens visas tillsammans. Beloppsindikationen använder mängdskillnaden och Workifys tonpris. Faktureringsstatus hämtas från Workify-importen.</p>
    <div className="toolbar">
      <label>Visa <select value={filter} onChange={event => setFilter(event.target.value)}>
        <option value="all">Alla poster</option>
        <option value="review">Att granska</option>
        <option value="matched">Med Workify-order</option>
        <option value="unmatched">Utan Workify-order</option>
      </select></label>{' '}
      <label>Sök <input type="search" value={search} onChange={event => setSearch(event.target.value)}
        placeholder="Order, kund, reg.nr eller material"/></label>
    </div>
    <p aria-live="polite">{visible.length} av {rows.length} poster</p>
    <div className="table-wrap">
      <table>
        <thead><tr>
          <th scope="col">Datum / order</th><th scope="col">Kund / reg.nr</th><th scope="col">Våg, ton</th>
          <th scope="col">Workify, ton</th><th scope="col">Skillnad, ton</th><th scope="col">Beloppsindikation, kr</th>
          <th scope="col">Status</th><th scope="col">Underlag</th>
        </tr></thead>
        <tbody>{visible.map(row => <tr key={row.tickets[0].id}>
          <td>{row.first_day === row.last_day ? row.last_day : `${row.first_day} – ${row.last_day}`}<br/>
            {row.order_number ? <OrderNumber value={row.order_number}/> : 'Orderreferens saknas'}</td>
          <td>{row.customers || '—'}<br/>{row.vehicles || '—'}<br/>{row.materials}</td>
          <td>{format(row.weighed_tonnes)}</td><td>{format(row.order_tonnes)}</td>
          <td>{format(row.difference_tonnes)}</td><td>{format(row.indicative_sek, money)}</td>
          <td>{comparisonLabels[row.comparison_status]}<br/>{billingLabels[row.billing_status]}</td>
          <td><Evidence row={row}/></td>
        </tr>)}
        {!visible.length && <tr><td colSpan={8}>Inga poster i urvalet.</td></tr>}</tbody>
      </table>
    </div>
  </section>;
}
