'use client';

import {useState, type FormEvent} from 'react';
import {stockholmToday} from '@/lib/kpi/period';

type ReviewRow = {
 fact_id: string;
 occurred_on: string;
 kind: 'cost' | 'revenue';
 source: string;
 amount: number;
 project: string | null;
 vehicle: string | null;
 unit_name: string | null;
 cost_center: string | null;
 description: string | null;
 allocation_state: 'probable' | 'unallocated';
 probability: {decision?: string; support?: number} | null;
 raw_id: string | null;
 reusable_project: string | null;
 saved_target: string | null;
};
type Candidate = {unit_id: string; support: number; signals: string[] | null};
type Review = {
 generation: string;
 review_count: number;
 items: ReviewRow[];
 units: {id: string; name: string}[];
 totals: {allocation_state: string; kind: string; rows: number; amount: number}[];
};
const money = new Intl.NumberFormat('sv-SE', {style: 'currency', currency: 'SEK', maximumFractionDigits: 2});
const signals: Record<string, string> = {
 registry_vehicle: 'Fordon i registret', registry_project: 'Projekt i registret',
 driver_day: 'Förarens TransPA-tid samma dag', driver_history: 'Förarens historik',
 same_order: 'Annan rad på samma order', document_registration: 'Registreringsnummer i underlaget',
 confirmed_learning: 'Tidigare bekräftade matchningar',
};
const states: Record<string, string> = {allocated: 'Fördelad', probable: 'Sannolikt fördelad', unallocated: 'Ofördelad'};

export function KpiAllocationReview() {
 const today = stockholmToday();
 const [from, setFrom] = useState(`${today.month >= 9 ? today.year : today.year - 1}-09-01`);
 const [to, setTo] = useState(`${today.year}-${String(today.month).padStart(2, '0')}-${String(today.day).padStart(2, '0')}`);
 const [data, setData] = useState<Review | null>(null);
 const [page, setPage] = useState(0);
 const [busy, setBusy] = useState(false);
 const [error, setError] = useState('');
 const [message, setMessage] = useState('');
 const [assessments, setAssessments] = useState<Record<string, Candidate[]>>({});

 async function load(next = 0) {
  setBusy(true);
  setError('');
  setMessage('');
  try {
   const query = new URLSearchParams({from, to, page: String(next)});
   const response = await fetch('/api/kpi/allocation-review?' + query, {cache: 'no-store'});
   const result = await response.json();
   if (!response.ok) throw new Error(result.error);
   setData(result);
   setAssessments({});
   setPage(next);
  } catch (cause) {
   setError(cause instanceof Error ? cause.message : 'Granskningskön kunde inte hämtas');
  } finally {
   setBusy(false);
  }
 }

 async function assess(row: ReviewRow) {
  if (!data) return;
  setBusy(true);
  setError('');
  try {
   const response = await fetch('/api/kpi/allocation-review', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({action: 'assess', generation: data.generation, fact: row.fact_id}),
   });
   const result = await response.json();
   if (!response.ok) throw new Error(result.error);
   setAssessments(current => ({...current, [row.fact_id]: result.candidates}));
  } catch (cause) {
   setError(cause instanceof Error ? cause.message : 'Förslagen kunde inte hämtas');
  } finally {
   setBusy(false);
  }
 }

 async function confirm(event: FormEvent<HTMLFormElement>, row: ReviewRow) {
  event.preventDefault();
  if (!data) return;
  const form = new FormData(event.currentTarget);
  const unit = String(form.get('unit') ?? '');
  setBusy(true);
  setError('');
  setMessage('');
  try {
   const response = await fetch('/api/kpi/allocation-review', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({generation: data.generation, fact: row.fact_id, unit, remember: form.has('remember')}),
   });
   const result = await response.json();
   if (!response.ok) throw new Error(result.error);
   setData(current => current && {...current, items: current.items.map(item =>
    item.fact_id === row.fact_id ? {...item, saved_target: unit} : item)});
   setMessage(result.queued
    ? 'Mappningen är sparad. Rapportunderlaget har köats för uppdatering.'
    : 'Mappningen är sparad och används vid nästa uppdatering av rapportunderlaget.');
  } catch (cause) {
   setError(cause instanceof Error ? cause.message : 'Mappningen kunde inte sparas');
  } finally {
   setBusy(false);
  }
 }

 return <section aria-busy={busy}>
  <p>Granska sannolika och ofördelade poster i den publicerade rapportversionen. Ofördelade belopp ligger kvar i Hubunderlaget och visas här separat. Evidenspoängen visar styrkan i underlaget för ett förslag.</p>
  <form className="filters" onSubmit={event => {event.preventDefault(); void load();}}>
   <label>Från<input type="date" value={from} required disabled={busy} onChange={event => {setFrom(event.target.value); setData(null);}}/></label>
   <label>Till<input type="date" value={to} required disabled={busy} onChange={event => {setTo(event.target.value); setData(null);}}/></label>
   <button type="submit" disabled={busy}>Hämta granskningskö</button>
  </form>
  {error && <p role="alert">{error}</p>}
  {message && <p role="status">{message}</p>}
  {data && <>
   <div className="table-wrap"><table>
    <thead><tr><th>Fördelning</th><th>Typ</th><th>Poster</th><th>Belopp</th></tr></thead>
    <tbody>{data.totals.map(total => <tr key={total.allocation_state + total.kind}>
     <td>{states[total.allocation_state]}</td><td>{total.kind === 'cost' ? 'Kostnad' : 'Intäkt'}</td>
     <td>{total.rows}</td><td>{money.format(total.amount)}</td>
    </tr>)}</tbody>
   </table></div>
   <h3>{data.review_count} poster att granska</h3>
   <div className="table-wrap"><table>
    <thead><tr><th>Post</th><th>Fördelning</th><th>Bekräfta enhet</th></tr></thead>
    <tbody>{data.items.map(row => <tr key={row.fact_id}>
     <td><strong>{money.format(row.amount)}</strong><br/>{row.occurred_on} · {row.source} · {row.kind === 'cost' ? 'Kostnad' : 'Intäkt'}
      <br/>{[row.description, row.project && 'Projekt ' + row.project, row.vehicle, row.cost_center && 'KST ' + row.cost_center].filter(Boolean).join(' · ')}
     </td>
     <td>{states[row.allocation_state]}{row.unit_name && <><br/>{row.unit_name}</>}
      {row.probability?.support != null && <><br/>Evidenspoäng {Math.round(row.probability.support * 100)} / 100</>}
      <br/><button type="button" className="secondary" disabled={busy} onClick={() => void assess(row)}>Ta fram förslag</button>
      {assessments[row.fact_id]?.length === 0 && <p>Inget förslag med tillräckligt underlag.</p>}
      {assessments[row.fact_id]?.map(candidate => <p key={candidate.unit_id}>
       {data.units.find(unit => unit.id === candidate.unit_id)?.name ?? 'Annan ekonomisk enhet'} · {Math.round(candidate.support * 100)} / 100
       <br/>{candidate.signals?.map(signal => signals[signal] ?? signal).join(', ')}
      </p>)}
     </td>
     <td>{row.saved_target ? <span>Sparad koppling till {data.units.find(unit => unit.id === row.saved_target)?.name ?? 'vald enhet'}</span>
      : row.raw_id && ['NEXT', 'Workify'].includes(row.source) ? <form onSubmit={event => void confirm(event, row)}>
       <label>Ekonomisk enhet<select name="unit" required defaultValue="" disabled={busy}>
        <option value="">Välj enhet</option>
        {data.units.map(unit => <option key={unit.id} value={unit.id}>{unit.name}</option>)}
       </select></label>
       {row.reusable_project && <label><input type="checkbox" name="remember" disabled={busy}/>
        Kom ihåg för NeXT-projekt {row.reusable_project} och samma typ av post från {row.occurred_on}</label>}
       <button type="submit" disabled={busy}>Spara mappning</button>
      </form> : <span>Granskas via källan eller ordinarie matchning.</span>}</td>
    </tr>)}</tbody>
   </table></div>
   <nav aria-label="Granskningssidor">
    <button type="button" disabled={busy || page === 0} onClick={() => void load(page - 1)}>Föregående</button>
    {' '}Sida {page + 1}{' '}
    <button type="button" disabled={busy || (page + 1) * 25 >= data.review_count} onClick={() => void load(page + 1)}>Nästa</button>
   </nav>
  </>}
 </section>;
}
